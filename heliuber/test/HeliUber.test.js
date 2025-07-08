// Test suite for HeliUber smart contracts
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("HeliUber", function () {
  let heliUber, mockStablecoin, booking, payment, accessControl;
  let owner, pilot, passenger, unauthorized;
  let stablecoinAddress;

  beforeEach(async function () {
    [owner, pilot, passenger, unauthorized] = await ethers.getSigners();

    // Deploy MockStablecoin
    const MockStablecoin = await ethers.getContractFactory("MockStablecoin");
    mockStablecoin = await MockStablecoin.deploy();
    await mockStablecoin.deployed();
    stablecoinAddress = mockStablecoin.address;

    // Deploy HeliUber
    const HeliUber = await ethers.getContractFactory("HeliUber");
    heliUber = await HeliUber.deploy(stablecoinAddress);
    await heliUber.deployed();

    // Get internal contracts
    booking = await ethers.getContractAt("Booking", await heliUber.booking());
    payment = await ethers.getContractAt("Payment", await heliUber.payment());
    accessControl = await ethers.getContractAt("AccessControl", heliUber.address);

    // Register pilot and passenger
    await accessControl.connect(owner).registerPilot(pilot.address);
    await accessControl.connect(passenger).registerPassenger(passenger.address);

    // Mint and approve stablecoins
    await mockStablecoin.connect(passenger).approve(heliUber.address, ethers.utils.parseUnits("1000", 6));
    await mockStablecoin.connect(passenger).mint(passenger.address, ethers.utils.parseUnits("1000", 6));
  });

  describe("Ride Booking", function () {
    it("should allow passenger to book a ride", async function () {
      const price = ethers.utils.parseUnits("100", 6);
      const destination = ethers.utils.formatBytes32String("Airport");
      await expect(heliUber.connect(passenger).bookRide(pilot.address, price, destination))
        .to.emit(heliUber, "RideBooked")
        .withArgs(0, passenger.address, pilot.address, price);
      
      const ride = await booking.rides(0);
      expect(ride.passenger).to.equal(passenger.address);
      expect(ride.pilot).to.equal(pilot.address);
      expect(ride.price).to.equal(price);
      expect(ride.status).to.equal(1); // RideStatus.Paid
    });

    it("should fail if pilot is not registered", async function () {
      const price = ethers.utils.parseUnits("100", 6);
      const destination = ethers.utils.formatBytes32String("Airport");
      await expect(heliUber.connect(passenger).bookRide(unauthorized.address, price, destination))
        .to.be.revertedWith("Invalid pilot");
    });
  });

  describe("Ride Confirmation", function () {
    let rideId, price;

    beforeEach(async function () {
      price = ethers.utils.parseUnits("100", 6);
      const destination = ethers.utils.formatBytes32String("Airport");
      await heliUber.connect(passenger).bookRide(pilot.address, price, destination);
      rideId = 0;
    });

    it("should allow passenger to confirm ride", async function () {
      await expect(heliUber.connect(passenger).confirmRide(rideId))
        .to.emit(heliUber, "RideConfirmed")
        .withArgs(rideId, passenger.address);
      
      const ride = await booking.rides(rideId);
      expect(ride.passengerConfirmed).to.be.true;
      expect(ride.status).to.equal(2); // RideStatus.PassengerConfirmed
    });

    it("should allow pilot to confirm ride", async function () {
      await expect(heliUber.connect(pilot).confirmRide(rideId))
        .to.emit(heliUber, "RideConfirmed")
        .withArgs(rideId, pilot.address);
      
      const ride = await booking.rides(rideId);
      expect(ride.pilotConfirmed).to.be.true;
    });

    it("should fail if unauthorized user tries to confirm", async function () {
      await expect(heliUber.connect(unauthorized).confirmRide(rideId))
        .to.be.revertedWith("Invalid role");
    });

    it("should fail if passenger confirms twice", async function () {
      await heliUber.connect(passenger).confirmRide(rideId);
      await expect(heliUber.connect(passenger).confirmRide(rideId))
        .to.be.revertedWith("Passenger already confirmed");
    });
  });

  describe("Payment Release", function () {
    let rideId, price;

    beforeEach(async function () {
      price = ethers.utils.parseUnits("100", 6);
      const destination = ethers.utils.formatBytes32String("Airport");
      await heliUber.connect(passenger).bookRide(pilot.address, price, destination);
      rideId = 0;
    });

    it("should release payment after both confirmations", async function () {
      const initialPilotBalance = await mockStablecoin.balanceOf(pilot.address);
      const initialCreatorBalance = await mockStablecoin.balanceOf(owner.address);
      const creatorFee = price.div(100);
      const pilotAmount = price.sub(creatorFee);

      await heliUber.connect(passenger).confirmRide(rideId);
      await heliUber.connect(pilot).confirmRide(rideId);

      await expect(heliUber.connect(pilot).confirmRide(rideId))
        .to.emit(heliUber, "RideCompleted")
        .withArgs(rideId, pilotAmount, creatorFee);

      const finalPilotBalance = await mockStablecoin.balanceOf(pilot.address);
      const finalCreatorBalance = await mockStablecoin.balanceOf(owner.address);

      expect(finalPilotBalance.sub(initialPilotBalance)).to.equal(pilotAmount);
      expect(finalCreatorBalance.sub(initialCreatorBalance)).to.equal(creatorFee);
    });

    it("should fail if only one party confirms", async function () {
      await heliUber.connect(passenger).confirmRide(rideId);
      await expect(payment.connect(pilot).releasePayment(rideId))
        .to.be.revertedWith("Not both confirmed");
    });
  });
});
