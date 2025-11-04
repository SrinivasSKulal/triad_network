// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SupplyChain {
    address public owner;
    
    enum Role { Manufacturer, Distributor, Retailer }
    enum ShipmentStatus { Created, InTransit, Delivered, Received }
    
    struct Participant {
        address participantAddress;
        Role role;
        string name;
        bool isRegistered;
    }
    
    struct Product {
        uint256 productId;
        string productName;
        address manufacturer;
        uint256 manufactureDate;
        string description;
    }
    
    struct Shipment {
        uint256 shipmentId;
        uint256 productId;
        address currentOwner;
        address previousOwner;
        ShipmentStatus status;
        uint256 createdDate;
        uint256 transferDate;
        uint256 receivedDate;
        string location;
    }
    
    struct ShipmentEvent {
        uint256 eventId;
        uint256 shipmentId;
        ShipmentStatus status;
        address actor;
        uint256 timestamp;
        string description;
    }
    
    mapping(address => Participant) public participants;
    mapping(uint256 => Product) public products;
    mapping(uint256 => Shipment) public shipments;
    mapping(uint256 => ShipmentEvent[]) public shipmentHistory;
    mapping(uint256 => address[]) public productOwnershipHistory;
    
    uint256 public productCount;
    uint256 public shipmentCount;
    uint256 public eventCount;
    
    event ParticipantRegistered(address participant, Role role, string name);
    event ProductCreated(uint256 productId, string productName, address manufacturer);
    event ShipmentCreated(uint256 shipmentId, uint256 productId, address creator);
    event ShipmentTransferred(uint256 shipmentId, address from, address to, ShipmentStatus status);
    event ShipmentReceived(uint256 shipmentId, address receiver, uint256 timestamp);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }
    
    modifier onlyRegistered() {
        require(participants[msg.sender].isRegistered, "Participant not registered");
        _;
    }
    
    modifier onlyManufacturer() {
        require(participants[msg.sender].role == Role.Manufacturer, "Only manufacturer can perform this action");
        _;
    }
    
    modifier onlyDistributor() {
        require(participants[msg.sender].role == Role.Distributor, "Only distributor can perform this action");
        _;
    }
    
    modifier onlyRetailer() {
        require(participants[msg.sender].role == Role.Retailer, "Only retailer can perform this action");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        productCount = 0;
        shipmentCount = 0;
        eventCount = 0;
    }
    
    // Register participants with their roles
    function registerParticipant(address _participant, Role _role, string memory _name) public onlyOwner {
        participants[_participant] = Participant({
            participantAddress: _participant,
            role: _role,
            name: _name,
            isRegistered: true
        });
        
        emit ParticipantRegistered(_participant, _role, _name);
    }
    
    // Manufacturer creates a product
    function createProduct(string memory _productName, string memory _description) public onlyRegistered onlyManufacturer returns(uint256) {
        productCount++;
        
        products[productCount] = Product({
            productId: productCount,
            productName: _productName,
            manufacturer: msg.sender,
            manufactureDate: block.timestamp,
            description: _description
        });
        
        emit ProductCreated(productCount, _productName, msg.sender);
        return productCount;
    }
    
    // Create shipment for a product
    function createShipment(uint256 _productId, string memory _location) public onlyRegistered returns(uint256) {
        require(products[_productId].productId != 0, "Product does not exist");
        require(products[_productId].manufacturer == msg.sender, "Only product manufacturer can create shipment");
        
        shipmentCount++;
        
        shipments[shipmentCount] = Shipment({
            shipmentId: shipmentCount,
            productId: _productId,
            currentOwner: msg.sender,
            previousOwner: address(0),
            status: ShipmentStatus.Created,
            createdDate: block.timestamp,
            transferDate: 0,
            receivedDate: 0,
            location: _location
        });
        
        // Add to ownership history
        productOwnershipHistory[_productId].push(msg.sender);
        
        // Record event
        _recordShipmentEvent(shipmentCount, ShipmentStatus.Created, "Shipment created by manufacturer");
        
        emit ShipmentCreated(shipmentCount, _productId, msg.sender);
        return shipmentCount;
    }
    
    // Transfer shipment to another participant
    function transferShipment(uint256 _shipmentId, address _to) public onlyRegistered {
        require(shipments[_shipmentId].shipmentId != 0, "Shipment does not exist");
        require(shipments[_shipmentId].currentOwner == msg.sender, "Only current owner can transfer shipment");
        require(participants[_to].isRegistered, "Recipient must be registered");
        
        // Check role-based transfer rules
        Role fromRole = participants[msg.sender].role;
        Role toRole = participants[_to].role;
        
        if (fromRole == Role.Manufacturer) {
            require(toRole == Role.Distributor, "Manufacturer can only transfer to Distributor");
        } else if (fromRole == Role.Distributor) {
            require(toRole == Role.Retailer, "Distributor can only transfer to Retailer");
        } else {
            revert("Retailer cannot transfer further");
        }
        
        shipments[_shipmentId].previousOwner = shipments[_shipmentId].currentOwner;
        shipments[_shipmentId].currentOwner = _to;
        shipments[_shipmentId].status = ShipmentStatus.InTransit;
        shipments[_shipmentId].transferDate = block.timestamp;
        
        // Add to ownership history
        productOwnershipHistory[shipments[_shipmentId].productId].push(_to);
        
        // Record event
        _recordShipmentEvent(_shipmentId, ShipmentStatus.InTransit, 
            string(abi.encodePacked("Shipment transferred from ", participants[msg.sender].name, " to ", participants[_to].name)));
        
        emit ShipmentTransferred(_shipmentId, msg.sender, _to, ShipmentStatus.InTransit);
    }
    
    // Receive shipment
    function receiveShipment(uint256 _shipmentId) public onlyRegistered {
        require(shipments[_shipmentId].shipmentId != 0, "Shipment does not exist");
        require(shipments[_shipmentId].currentOwner == msg.sender, "Only current owner can receive shipment");
        require(shipments[_shipmentId].status == ShipmentStatus.InTransit, "Shipment must be in transit");
        
        shipments[_shipmentId].status = ShipmentStatus.Received;
        shipments[_shipmentId].receivedDate = block.timestamp;
        
        // Record event
        _recordShipmentEvent(_shipmentId, ShipmentStatus.Received, 
            string(abi.encodePacked("Shipment received by ", participants[msg.sender].name)));
        
        emit ShipmentReceived(_shipmentId, msg.sender, block.timestamp);
    }
    
    // Internal function to record shipment events
    function _recordShipmentEvent(uint256 _shipmentId, ShipmentStatus _status, string memory _description) internal {
        eventCount++;
        shipmentHistory[_shipmentId].push(ShipmentEvent({
            eventId: eventCount,
            shipmentId: _shipmentId,
            status: _status,
            actor: msg.sender,
            timestamp: block.timestamp,
            description: _description
        }));
    }
    
    // Query functions
    function getProduct(uint256 _productId) public view returns(Product memory) {
        require(products[_productId].productId != 0, "Product does not exist");
        
        // Access control: Only participants involved in the product's supply chain can view
        bool hasAccess = false;
        for(uint i = 0; i < productOwnershipHistory[_productId].length; i++) {
            if(productOwnershipHistory[_productId][i] == msg.sender) {
                hasAccess = true;
                break;
            }
        }
        require(hasAccess || msg.sender == owner, "Access denied: You are not part of this product's supply chain");
        
        return products[_productId];
    }
    
    function getShipment(uint256 _shipmentId) public view returns(Shipment memory) {
        require(shipments[_shipmentId].shipmentId != 0, "Shipment does not exist");
        
        // Access control: Only current owner, previous owners, or owner can view
        require(
            shipments[_shipmentId].currentOwner == msg.sender ||
            shipments[_shipmentId].previousOwner == msg.sender ||
            msg.sender == owner,
            "Access denied: You are not authorized to view this shipment"
        );
        
        return shipments[_shipmentId];
    }
    
    function getShipmentHistory(uint256 _shipmentId) public view returns(ShipmentEvent[] memory) {
        require(shipments[_shipmentId].shipmentId != 0, "Shipment does not exist");
        
        // Access control: Only participants involved in the shipment can view history
        require(
            shipments[_shipmentId].currentOwner == msg.sender ||
            shipments[_shipmentId].previousOwner == msg.sender ||
            msg.sender == owner,
            "Access denied: You are not authorized to view this shipment history"
        );
        
        return shipmentHistory[_shipmentId];
    }
    
    function getProductHistory(uint256 _productId) public view returns(address[] memory) {
        require(products[_productId].productId != 0, "Product does not exist");
        
        // Access control
        bool hasAccess = false;
        for(uint i = 0; i < productOwnershipHistory[_productId].length; i++) {
            if(productOwnershipHistory[_productId][i] == msg.sender) {
                hasAccess = true;
                break;
            }
        }
        require(hasAccess || msg.sender == owner, "Access denied");
        
        return productOwnershipHistory[_productId];
    }
    
    function getParticipantRole(address _participant) public view returns(Role) {
        require(participants[_participant].isRegistered, "Participant not registered");
        return participants[_participant].role;
    }
}