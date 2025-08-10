# HashRipper


Work in progress macOS app to manage AxeOS based bitcoin miners. 

### Important
Requires NerdQAxe miners to be on [AxeOS version 1.0.30+](https://github.com/shufps/ESP-Miner-NerdQAxePlus/releases/tag/v1.0.30) due to requiring macAddress information of the miner.

## Features:
- Uses swarm scan approach to find miners on network
- Quick overview of miners
- Setup miner profiles to quickly swap/try mining pools
- Shows firmware releases for the devices you have
- Simple onboarding for new miner devices by using your saved profiles

## Future Features
- Firmware download and rollouts/rollbacks
- ASIC health monitoring for multi-asic devices
- Profile export to share pool configs

## Example App screenshots:

### Main Hash Operations
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 12 34 PM" src="https://github.com/user-attachments/assets/c3737c06-7761-4913-9324-a4bf9132d710" />

### Profile Management
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 12 40 PM" src="https://github.com/user-attachments/assets/7114643f-26e6-405a-8982-e96375175e0d" />

### Firmware Version lookups
<img width="1853" height="1172" alt="Screenshot 2025-08-09 at 10 59 42 PM" src="https://github.com/user-attachments/assets/cd994f1a-e9f9-44ff-9633-fb53d342abc3" />


New AxeOS Miner Device Onboarding
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 18 38 PM" src="https://github.com/user-attachments/assets/420ff9fa-5f7f-4ee4-8b9a-909ac679ed5a" />

### Profile Deploys
Step 1. Select Profile
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 19 58 PM" src="https://github.com/user-attachments/assets/bbea5a03-a8f2-4a59-8e53-bb6a3ca10969" />

Step 2. Select Miners
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 20 15 PM" src="https://github.com/user-attachments/assets/8a080a8c-e253-477e-b801-e0a1e4416440" />

Step 3. Deploy
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 20 25 PM" src="https://github.com/user-attachments/assets/8186a391-0125-494c-9c08-523e82a50e4b" />

### Record Websocket data to a file
<img width="1450" height="947" alt="Screenshot 2025-08-09 at 10 21 12 PM" src="https://github.com/user-attachments/assets/b75ea837-dfaa-4e78-a1c1-b8ef1ffeb086" />


At some point I'll build a release binary but until then if you want to give it a go

## Building the app
- Download Xcode from apple or macOS app store
- Open the file HashRipper/app/HashRipper.xcodeproj
- Make sure the destination at the top of Xcode shows `HashRipper > My Mac`
  <img width="626" height="51" alt="Screenshot 2025-07-12 at 8 31 34 PM" src="https://github.com/user-attachments/assets/c0826340-c29e-4200-8616-d53dd144a12d" />
- Hit the top play button or on the keyboard hit the keyboard shortcut `cmd + r` to run the app


# Fund More Features
If you find it useful help fund more features by sending some sats to one of the following:

Lightning Bitcoin Address mattsellars@vipsats.app

![IMG_1B6AB58B02B3-1](https://github.com/user-attachments/assets/8ff8be1a-fb58-4bc6-bbab-fd31c227bfb5)

Direct Bitcoin Address

<img width="339" height="289" alt="Screenshot 2025-07-12 at 8 42 51 PM" src="https://github.com/user-attachments/assets/330fc042-ab61-4198-b2ea-690b0f84cac5" />




