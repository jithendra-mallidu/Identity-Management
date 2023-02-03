// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*Errors*/
error Identity_TxnSenderNotOwner();
error Identity_TxnSenderNotPermittedAgency();
error Identity_AgencyAlreadyAdded();
error Identity_CitizenAlreadyAdded();
error Identity_AgencyAlreadyBanned();
error Identity_CitizenAlreadyBanned();
error Identity_AgencyAlreadyPermitted();
error Identity_AgencyAlreadyVerifiedCitizen();
error Identity_InvalidAgencyRegistrationNumber();

contract Identity_Management {
    /*  Type Declarations*/
    enum IdentityAgencyState{
        BANNED,
        PERMITTED
        // by default agency is not PERMITTED
    }

    enum IdentityCitizenState{
        BANNED,
        PERMITTED
        // By default citizen ID is also not allowed not PERMITTED
    }

    enum IdentityGender{
        MALE,
        FEMALE,
        OTHER
    }

    struct Citizen{
        bytes32                 profilePicHash;
        string                  citizenName;
        IdentityGender          gender;
        string                  dateOfBirth;
        uint256                 idVerifications; // Number of times the Citizen ID has been verified by different agencies
        IdentityCitizenState    citizenState;
    }

    struct Agency{
        uint256                 agencyRegistrationNumber;
        string                  agencyName;
        IdentityAgencyState     agencyState;
        /* string               agencyDescription (I believe this is not a good idea to store
                                description of an agency on the blockchain since this is not something
                                which cannot be compromised upon, this can verwell be stored on 
                                centralized MHRE servers
        */
    }
    
    /*State Variables*/
   
    //Store the owner of the contract
    address private immutable i_owner;
    //stores list of all agencies in an array
    address[] private s_agencyArray;
    //stores list of all citizen ID's in an array
    uint256[] private s_citizenArray;
    //number that will be used to generate a random number
    uint256 private s_nounce;
    //The maximum value of the registration number for an agency
    uint256 private MAX_REGISTRATION_NUMBER = 999999999999999;

    /*Mappings*/
    
    //stores citizens aadhar card number and citizen struct as key value pair respectively
    mapping(uint256 => Citizen) private s_citizenMapping;

    //stores agency address and agency struct as key value pair respectively
    mapping(address => Agency) private s_agencyMapping;

    //stores citizen adhar number against the array of agency addresses who have verified the citizen id
    mapping(uint256 => address[]) private s_citizenToAgencyMapping;

    /*Events*/

    event IdentityAgencyAdded(uint256 indexed agencyIDNumber, string indexed agencyName);
    event IdentityAgencybanned(address indexed agencyAddress, uint256 indexed agencyRegistrationNumber);
    event IdentityCitizenIDAuthentication(uint256 indexed aadharNumber, address indexed agencyAddress);
    event IdentityCitizenIDMalicious(uint256 indexed aadharNumber, address indexed agencyAddress);
    event IdentityCitizenIDBanned(uint256 indexed aadharNumber, address indexed agencyAddress);
    event IdentityCitizenAdded(uint256 indexed aadharNumber);

    /*Modifiers*/

    // only owner of the contract that is MHRE
    modifier onlyOwner() {
        if (msg.sender != i_owner){
            revert Identity_TxnSenderNotOwner();
        } 
        _;
    }
    // only those agencies who are permitted by MHRE
    modifier onlyPermittedAgency() {
        if (s_agencyMapping[msg.sender].agencyState == IdentityAgencyState.BANNED){
            revert Identity_TxnSenderNotPermittedAgency();
        }
        _;
    }
    /*Functions*/

    //setting up of variables at the time of deployment of contract
    constructor(){
        //setting the owner
        i_owner = msg.sender;
        /*setting the nounce used for getting the random number (initial value is initialized as
        a big prime number*/
        s_nounce = 16661;
        // adding MHRE as the agency
        s_agencyMapping[msg.sender] = Agency(MAX_REGISTRATION_NUMBER, "MHRE", IdentityAgencyState.PERMITTED);
    }
    // this function generates a random number
    function getRandomNumber() private onlyPermittedAgency returns(uint256){
        s_nounce++;
        return(uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, s_nounce)))%MAX_REGISTRATION_NUMBER);
    }

    //this function adds a new agency
    // only owner or MHRE can add a new agency
    function addAgency(address agencyAddress, string memory _agencyName) external onlyOwner{
        // Agency should not be already added by MHRE
        if(s_agencyMapping[agencyAddress].agencyRegistrationNumber != 0){
            revert Identity_AgencyAlreadyAdded();
        }
        // Agency should not have the registration Number same as MHRE

        if(s_agencyMapping[agencyAddress].agencyRegistrationNumber == MAX_REGISTRATION_NUMBER){
            revert Identity_InvalidAgencyRegistrationNumber();
        }
        uint256 randomNumber = getRandomNumber();
        s_agencyMapping[agencyAddress] = Agency(randomNumber, _agencyName, IdentityAgencyState.PERMITTED);
        s_agencyArray.push(agencyAddress);

        emit IdentityAgencyAdded(randomNumber, _agencyName);
    }
    // function to generate ID for the citizen
    // only agencies permitted by the MHRE can call this function
    function addCitizen(
        string memory profilePicData,
        string memory _citizenName,
        IdentityGender _gender,
        string memory _dateOfBirth,
        uint256 aadharNumber
    ) external onlyPermittedAgency{

        // if citizen ID is already generated then revert the transaction
        if(uint(s_citizenMapping[aadharNumber].profilePicHash) != 0){
            revert Identity_CitizenAlreadyAdded();
        }

        s_citizenMapping[aadharNumber] = Citizen(keccak256(bytes(profilePicData)), _citizenName, _gender, _dateOfBirth, 1, IdentityCitizenState.PERMITTED);
        s_citizenArray.push(aadharNumber);
        emit IdentityCitizenAdded(aadharNumber);        
    }

    // function used to check if agency can verify a particular citizen's ID
    // only agencies permitted by MHRE can call this function

    function agencyCanVerifyCitizen (uint256 aadharNumber) public view onlyPermittedAgency returns(bool){
        address[] memory tempArray = s_citizenToAgencyMapping[aadharNumber];
        bool canUpdate;

        if(tempArray.length > 1){
            canUpdate = true;

            for(uint256 i =0; i< tempArray.length; i++){
                if(tempArray[i]==msg.sender){
                    canUpdate = false;
                    break;
                }
            }
        }
        else if (tempArray.length == 1){
            if(tempArray[0]==msg.sender){
                canUpdate = false;
            }
            else{
                canUpdate = true;
            }
        }
        else {
            canUpdate = true;
        }
        return canUpdate;
    }

    // function that verifies citizen's ID
    // only agencies permitted by MHRE can call this function
    function verifyCitizenId(uint256 aadharNumber, bool isCitizenIdValid) external onlyPermittedAgency{

        /*Agency does offchain verification =>
        1. Fetch details of a citizen from s_citizenMapping using aadharNumber as key (say aadhar number is 123 for example)
        2. Fetch details of the citizen with the aadharNumber 123 from the off-chain database
        3. compare the two details, if they match => citizenID is verified otherwise notverified
            verified    => verifyCitizenId is called with true as arguement 
            notVerified => verifyCitizenId is called with false as argument
        */

        // if an agency has already verified a particular ID they can't verify it again
        if(agencyCanVerifyCitizen(aadharNumber) == false){
            revert Identity_AgencyAlreadyVerifiedCitizen();
        }
        // if agency tests that ID is valid then they call the function with true parameter and this part is executed
        if(isCitizenIdValid == true){
            s_citizenMapping[aadharNumber].idVerifications ++;
            emit IdentityCitizenIDAuthentication(aadharNumber, msg.sender);
        }
        // if agency tests that ID is malicious then they call the function with false parameter and this part is executed
        else {
            s_citizenMapping[aadharNumber].idVerifications --;
            // if the ID gets many down votes such that s_citizenMapping[aadharNumber].idverifications becomes 0 then ban the ID
            // citizen will have to generate a new ID again as this ID is fake/malicious
            if(s_citizenMapping[aadharNumber].idVerifications == 0){
                // calling the functions that bans the ID
                banCitizenID(aadharNumber);
            }
            // if the s_citizenMapping[aadharNumber].idVerifications does not go down to zero then
            else{
                emit IdentityCitizenIDMalicious(aadharNumber, msg.sender);
            }
        }
        // traking which id is verified by what all agencies 
        s_citizenToAgencyMapping[aadharNumber].push(msg.sender);
    }

    // function that bans an agency 
    // only MHRE can call this function

    function permitAgency(address agencyAddress) external onlyOwner{
        if(s_agencyMapping[agencyAddress].agencyState == IdentityAgencyState.PERMITTED){
            revert Identity_AgencyAlreadyPermitted();
        }
        s_agencyMapping[agencyAddress].agencyState = IdentityAgencyState.PERMITTED;
        emit IdentityAgencybanned(agencyAddress, s_agencyMapping[agencyAddress].agencyRegistrationNumber);
        
    }

    // only agencies permitted by MHRE can call this function
    // this function bans a citizen's ID 
    // if a citizen is banned then (s)he will have to get another ID generated
    function banCitizenID (uint256 aadharNumber) internal onlyPermittedAgency {
        if(s_citizenMapping[aadharNumber].citizenState == IdentityCitizenState.BANNED){
            revert Identity_CitizenAlreadyBanned();
        }
        s_citizenMapping[aadharNumber].citizenState == IdentityCitizenState.BANNED;
        emit IdentityCitizenIDBanned(aadharNumber, msg.sender);
    }

    // fucntion to get details of owner of the contract
    function getOwner() external view returns(address, Agency memory){
        return (i_owner, s_agencyMapping[i_owner]);
    }

    // function to get derails of an agency
    function getAgencyByAddress(address agencyAddress) external view returns(Agency memory){
        return(s_agencyMapping[agencyAddress]);
    }

    // fucntion to get details of  citizen

    function getCitizenByAadharNumber(uint256 aadharNumber) external view returns(Citizen memory){
        return(s_citizenMapping[aadharNumber]);
    }

    // function to get details of which citizen id was verified by what all agencies

    function getCitizenToAgencyMapping(uint256 aadharNumber) external view returns(address[] memory){
        return(s_citizenToAgencyMapping[aadharNumber]);
    }

}