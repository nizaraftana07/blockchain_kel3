// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BMWSupplyChain v1.1
/// @notice Prototipe pelacakan mobil BMW: Pabrik -> QC -> Distributor -> Dealer -> Pembeli
contract BMWSupplyChain {
    enum Role { None, Pabrik, Inspektur, Distributor, Dealer }
    enum ModelBMW { Seri3, Seri5, X5, iX }
    enum Status { Diproduksi, LulusQC, Ditolak, DalamPengiriman, Diterima, Terjual }

    struct Car {
        uint256 id;
        string vin;
        ModelBMW model;
        uint16 tahunProduksi;
        address pabrik;
        address pemilik;
        address penerima;
        Status status;
        uint256 diperbarui;
    }

    address public admin;
    uint256 public jumlahMobil;

    mapping(address => Role) public roles;
    mapping(uint256 => Car) private cars;
    mapping(bytes32 => bool) private vinTerdaftar;

    event ParticipantRegistered(address indexed akun, Role role);
    event CarCreated(uint256 indexed id, string vin, ModelBMW model, address indexed pabrik);
    event CarInspected(uint256 indexed id, address indexed inspektur, bool lulus);
    event CarShipped(uint256 indexed id, address indexed dari, address indexed ke);
    event CarReceived(uint256 indexed id, address indexed penerima);
    event CarSold(uint256 indexed id, address indexed dealer, address indexed pembeli);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Akses ditolak: hanya admin");
        _;
    }

    modifier onlyRole(Role _role) {
        require(roles[msg.sender] == _role, "Akses ditolak: peran tidak sesuai");
        _;
    }

    modifier mobilAda(uint256 _id) {
        require(_id > 0 && _id <= jumlahMobil, "Mobil tidak ditemukan");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function registerParticipant(address _akun, Role _role) external onlyAdmin {
        require(_akun != address(0), "Alamat tidak valid");
        require(_role != Role.None, "Peran tidak valid");
        require(roles[_akun] == Role.None, "Akun sudah terdaftar");
        roles[_akun] = _role;
        emit ParticipantRegistered(_akun, _role);
    }

    function createCar(string calldata _vin, ModelBMW _model, uint16 _tahun)
        external onlyRole(Role.Pabrik)
    {
        require(bytes(_vin).length == 17, "VIN harus 17 karakter");
        require(_tahun >= 2000 && _tahun <= 2100, "Tahun produksi tidak valid");

        bytes32 vinHash = keccak256(bytes(_vin));
        require(!vinTerdaftar[vinHash], "VIN sudah terdaftar");
        vinTerdaftar[vinHash] = true;

        jumlahMobil++;
        cars[jumlahMobil] = Car({
            id: jumlahMobil,
            vin: _vin,
            model: _model,
            tahunProduksi: _tahun,
            pabrik: msg.sender,
            pemilik: msg.sender,
            penerima: address(0),
            status: Status.Diproduksi,
            diperbarui: block.timestamp
        });
        emit CarCreated(jumlahMobil, _vin, _model, msg.sender);
    }

    function inspectCar(uint256 _id, bool _lulus)
        external mobilAda(_id) onlyRole(Role.Inspektur)
    {
        Car storage c = cars[_id];
        require(c.status == Status.Diproduksi, "Mobil sudah/tidak bisa diinspeksi");
        c.status = _lulus ? Status.LulusQC : Status.Ditolak;
        c.diperbarui = block.timestamp;
        emit CarInspected(_id, msg.sender, _lulus);
    }

    /// @dev Alur ketat: Pabrik -> Distributor, lalu Distributor -> Dealer.
    function shipCar(uint256 _id, address _ke) external mobilAda(_id) {
        Car storage c = cars[_id];
        require(msg.sender == c.pemilik, "Akses ditolak: bukan pemilik mobil");
        require(
            c.status == Status.LulusQC || c.status == Status.Diterima,
            "Mobil belum lulus QC atau status tidak memungkinkan"
        );
        require(_ke != address(0) && _ke != msg.sender, "Alamat tujuan tidak valid");
        require(
            roles[_ke] == Role.Distributor || roles[_ke] == Role.Dealer,
            "Tujuan harus Distributor atau Dealer terdaftar"
        );

        if (roles[msg.sender] == Role.Pabrik) {
            require(roles[_ke] == Role.Distributor, "Pabrik hanya boleh kirim ke Distributor");
            require(c.status == Status.LulusQC, "Pabrik hanya boleh kirim setelah lulus QC");
        } else if (roles[msg.sender] == Role.Distributor) {
            require(roles[_ke] == Role.Dealer, "Distributor hanya boleh kirim ke Dealer");
            require(c.status == Status.Diterima, "Distributor harus menerima mobil dahulu");
        } else {
            revert("Hanya Pabrik atau Distributor yang boleh mengirim");
        }

        c.status = Status.DalamPengiriman;
        c.penerima = _ke;
        c.diperbarui = block.timestamp;
        emit CarShipped(_id, msg.sender, _ke);
    }

    function receiveCar(uint256 _id) external mobilAda(_id) {
        Car storage c = cars[_id];
        require(c.status == Status.DalamPengiriman, "Mobil tidak sedang dikirim");
        require(msg.sender == c.penerima, "Bukan penerima yang dituju");
        c.pemilik = msg.sender;
        c.penerima = address(0);
        c.status = Status.Diterima;
        c.diperbarui = block.timestamp;
        emit CarReceived(_id, msg.sender);
    }

    function sellCar(uint256 _id, address _pembeli)
        external mobilAda(_id) onlyRole(Role.Dealer)
    {
        Car storage c = cars[_id];
        require(msg.sender == c.pemilik, "Akses ditolak: bukan pemilik mobil");
        require(c.status == Status.Diterima, "Mobil belum diterima dealer / sudah terjual");
        require(_pembeli != address(0), "Alamat pembeli tidak valid");
        require(roles[_pembeli] == Role.None, "Pembeli tidak boleh peserta supply chain");
        c.pemilik = _pembeli;
        c.status = Status.Terjual;
        c.diperbarui = block.timestamp;
        emit CarSold(_id, msg.sender, _pembeli);
    }

    function getCar(uint256 _id) external view mobilAda(_id) returns (Car memory) {
        return cars[_id];
    }
}