-- Create the database
CREATE DATABASE tbs;
USE tbs;

-- Users table
CREATE TABLE Users (
    UserID INT PRIMARY KEY,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    DOB DATE NOT NULL,
    Age INT,
    Gender CHAR(1) CHECK (Gender IN ('M', 'F')),
    Email VARCHAR(100) UNIQUE NOT NULL,
    Phone VARCHAR(15) NOT NULL,
    Address VARCHAR(255),
    Password VARCHAR(255) NOT NULL -- Store hashed password
);

-- Packages table
CREATE TABLE Packages (
    PackageID INT PRIMARY KEY,
    Price DECIMAL(10, 2) NOT NULL,
    PackageDescription VARCHAR(255),
    StartDate DATE,
    EndDate DATE
);

-- Payment table
CREATE TABLE Payment (
    PaymentID INT PRIMARY KEY,
    Amount DECIMAL(10, 2) NOT NULL,
    PaymentStatus INT CHECK (PaymentStatus IN (0, 1)) -- 0: Pending, 1: Complete
);

-- Booking table
CREATE TABLE Booking (
    BookingID INT PRIMARY KEY,
    BookingStatus INT CHECK (BookingStatus IN (0, 1)), -- 0: Cancelled, 1: Confirmed
    PackageID INT NOT NULL,
    PaymentID INT,
    FOREIGN KEY (PackageID) REFERENCES Packages(PackageID),
    FOREIGN KEY (PaymentID) REFERENCES Payment(PaymentID)
);

-- Hotels table
CREATE TABLE Hotels (
    HotelID VARCHAR(10) PRIMARY KEY,
    HotelName VARCHAR(100) NOT NULL,
    HotelLocation VARCHAR(100),
    PricePerRoom DECIMAL(10, 2),
    areMealsProvided INT CHECK (areMealsProvided IN (0, 1)),
    ACAvailability INT CHECK (ACAvailability IN (0, 1))
);

-- Transport table (Base transport entity)
CREATE TABLE Transport (
    TransportID VARCHAR(10) PRIMARY KEY,
    TicketPrice DECIMAL(10, 2),
    ArrivalTime TIME,
    ArrivalLocation VARCHAR(100),
    DepartureTime TIME,
    DepartureLocation VARCHAR(100)
);

-- Ship (subclass of Transport)
CREATE TABLE Ship (
    TransportID VARCHAR(10) PRIMARY KEY,
    CruiseName VARCHAR(100),
    CabinType VARCHAR(50),
    FOREIGN KEY (TransportID) REFERENCES Transport(TransportID)
);

-- Flight (subclass of Transport)
CREATE TABLE Flight (
    TransportID VARCHAR(10) PRIMARY KEY,
    AirlineName VARCHAR(100),
    FOREIGN KEY (TransportID) REFERENCES Transport(TransportID)
);

-- Train (subclass of Transport)
CREATE TABLE Train (
    TransportID VARCHAR(10) PRIMARY KEY,
    TrainType VARCHAR(50),
    TrainName VARCHAR(100),
    FOREIGN KEY (TransportID) REFERENCES Transport(TransportID)
);

-- Bus (subclass of Transport)
CREATE TABLE Bus (
    TransportID VARCHAR(10) PRIMARY KEY,
    is_AC INT CHECK (is_AC IN (0, 1)),
    FOREIGN KEY (TransportID) REFERENCES Transport(TransportID)
);

-- Destinations table
CREATE TABLE Destinations (
    DestinationID INT PRIMARY KEY,
    DestinationName VARCHAR(100) NOT NULL,
    isInternational INT CHECK (isInternational IN (0, 1))
);

-- International (subclass of Destinations)
CREATE TABLE International (
    DestinationID INT PRIMARY KEY,
    EmbassyContact VARCHAR(15),
    VISAReqd INT CHECK (VISAReqd IN (0, 1)),
    FOREIGN KEY (DestinationID) REFERENCES Destinations(DestinationID)
);

-- Book_Seat table (seats booked for a transport)
CREATE TABLE Book_Seat (
    TransportID VARCHAR(10),
    SeatNumber INT,
    PRIMARY KEY (TransportID, SeatNumber),
    FOREIGN KEY (TransportID) REFERENCES Transport(TransportID)
);

-- Users_Booking (many-to-many relationship between Users and Bookings)
CREATE TABLE Users_Booking (
    UserID INT,
    BookingID INT,
    PRIMARY KEY (UserID, BookingID),
    FOREIGN KEY (UserID) REFERENCES Users(UserID),
    FOREIGN KEY (BookingID) REFERENCES Booking(BookingID)
);

-- PackageInfo table (destinations & associated travel/accommodation for each package)
CREATE TABLE PackageInfo (
    PackageID INT,
    DestNumber INT,
    DestinationID INT,
    HotelID VARCHAR(10),
    TransportID VARCHAR(10),
    PRIMARY KEY (PackageID, DestNumber),
    FOREIGN KEY (PackageID) REFERENCES Packages(PackageID),
    FOREIGN KEY (DestinationID) REFERENCES Destinations(DestinationID),
    FOREIGN KEY (HotelID) REFERENCES Hotels(HotelID),
    FOREIGN KEY (TransportID) REFERENCES Transport(TransportID)
);
-- ================================================================================================
-- ================================================================================================

-- TRIGGERS
-- Trigger to hash out passwords 
DELIMITER $$

CREATE TRIGGER hash_password_before_insert
BEFORE INSERT ON Users
FOR EACH ROW
BEGIN
    SET NEW.Password = SHA2(NEW.Password, 256);
END$$

DELIMITER ;

-- /////////////////////////////////////////////////////////////

-- trigger to hash passwords on updation
-- Only re-hash when the password column actually changed. Without this check,
-- any other UPDATE on the row (e.g. CALL UpdateUserAge) hashed the stored hash
-- again, and that user could no longer log in.
DELIMITER $$

CREATE TRIGGER hash_password_before_update
BEFORE UPDATE ON Users
FOR EACH ROW
BEGIN
    IF NOT (NEW.Password <=> OLD.Password) THEN
        SET NEW.Password = SHA2(NEW.Password, 256);
    END IF;
END$$

DELIMITER ;

-- /////////////////////////////////////////////////////////////

-- Trigger to check if BookingStatus is True, only then can a PaymentID exist
DELIMITER //

CREATE TRIGGER trg_SetPaymentID_Null
BEFORE INSERT ON Booking
FOR EACH ROW
BEGIN
    IF NEW.BookingStatus = 0 THEN
        SET NEW.PaymentID = NULL;
    END IF;
END; //

DELIMITER ;

-- /////////////////////////////////////////////////////////////

-- Trigger to check if BookingStatus is True, only then can a PaymentID exist but an update trigger
DELIMITER //

CREATE TRIGGER trg_SetPaymentID_Null_On_Update
BEFORE UPDATE ON Booking
FOR EACH ROW
BEGIN
    IF NEW.BookingStatus = 0 THEN
        SET NEW.PaymentID = NULL;
    END IF;
END; //

DELIMITER ;

-- ================================================================================================
-- ================================================================================================

-- FUNCTIONS
DELIMITER //
CREATE FUNCTION GetPackagePrimaryDestinationName (p_PackageID INT)
RETURNS VARCHAR(100)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE dest_name VARCHAR(100);

    SELECT d.DestinationName
    INTO dest_name
    FROM PackageInfo pi
    JOIN Destinations d ON pi.DestinationID = d.DestinationID
    WHERE pi.PackageID = p_PackageID
      AND pi.DestNumber = 1 
    LIMIT 1; 

    RETURN COALESCE(dest_name, 'N/A'); 
END //
DELIMITER ;

-- /////////////////////////////////////////////////////////////

DELIMITER //

CREATE FUNCTION UserHasConfirmedInternationalBookings (p_UserID INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_has_international INT DEFAULT 0; 
    SELECT 1 INTO v_has_international
    WHERE EXISTS (
        SELECT 1 
        FROM Users_Booking ub
        JOIN Booking b ON ub.BookingID = b.BookingID
        JOIN PackageInfo pi ON b.PackageID = pi.PackageID
        JOIN Destinations d ON pi.DestinationID = d.DestinationID
        WHERE ub.UserID = p_UserID       
          AND b.BookingStatus = 1      
          AND d.isInternational = 1    
        LIMIT 1 
    );

    RETURN v_has_international; 
END //
DELIMITER ;

-- ================================================================================================
-- ================================================================================================

-- PROCEDURES
-- Procedure1: UpdateUserAge
DELIMITER $$

CREATE PROCEDURE UpdateUserAge(IN uID INT)
BEGIN
    UPDATE Users
    SET Age = TIMESTAMPDIFF(YEAR, DOB, CURDATE())
    WHERE UserID = uID;
END $$

DELIMITER ;

-- /////////////////////////////////////////////////////////////

-- Procedure2: GetUserBookingCount
DELIMITER $$

CREATE PROCEDURE GetUserBookingCount(IN uID INT)
BEGIN
    DECLARE totalBookings INT;

    SELECT COUNT(*) INTO totalBookings
    FROM Users_Booking
    WHERE UserID = uID;

    SELECT CONCAT('User with ID ', uID, ' has ', totalBookings, ' booking(s).') AS BookingInfo;
END$$

DELIMITER ;