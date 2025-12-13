# HashRipper


Work in progress macOS app to manage AxeOS and Nerd*OS based bitcoin miners. 

### Important
Requires NerdQAxe miners to be on [AxeOS version 1.0.30+](https://github.com/shufps/ESP-Miner-NerdQAxePlus/releases/tag/v1.0.30) due to requiring macAddress information of the miner.

## Features:
- Uses swarm scan approach to find miners on network
- Quick overview of miners
- Setup miner profiles to quickly swap/try mining pools
- Shows firmware releases for the devices you have, downloaded firmware management, and firmware deployments.
- Simple onboarding for new miner devices by using your saved profiles

## Future Features
- ASIC health monitoring for multi-asic devices

## Example App screenshots:

### Main Hash Operations
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 12 34 PM" src="https://github.com/user-attachments/assets/c3737c06-7761-4913-9324-a4bf9132d710" />

### Profile Management
Save miner profiles to switch mining pools easily. Define profiles, duplicate and swap primary secondary pool configurations, etc. You can also export profiles to back them up or share with friends.
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 12 40 PM" src="https://github.com/user-attachments/assets/7114643f-26e6-405a-8982-e96375175e0d" />

### Firmware Version lookups and downloads
Easily see available firmware updates and download related files from the github release
<img width="1477" height="1094" alt="Screenshot 2025-08-12 at 12 46 16 AM" src="https://github.com/user-attachments/assets/96a0b015-4548-4573-a086-3e14170b048c" />


New AxeOS Miner Device Onboarding
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 18 38 PM" src="https://github.com/user-attachments/assets/420ff9fa-5f7f-4ee4-8b9a-909ac679ed5a" />

### Profile Deploys
Step 1. Select Profile
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 19 58 PM" src="https://github.com/user-attachments/assets/bbea5a03-a8f2-4a59-8e53-bb6a3ca10969" />

Step 2. Select Miners
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 20 15 PM" src="https://github.com/user-attachments/assets/8a080a8c-e253-477e-b801-e0a1e4416440" />

Step 3. Deploy
<img width="1455" height="1006" alt="Screenshot 2025-07-12 at 8 20 25 PM" src="https://github.com/user-attachments/assets/8186a391-0125-494c-9c08-523e82a50e4b" />

### Record Websocket data
Stream web socket data to search/filter in real time and/or save out the raw logs to a file. You can select and copy text from the log in this view as well.
<img width="1012" height="840" alt="Screenshot 2025-12-13 at 7 43 04 AM" src="https://github.com/user-attachments/assets/23c19f88-bea4-45bd-9b0d-6577d7edc9e5" />



### Firmware deployments Manager (New · Beta)
Similar behavior to the original but now keeps historical data so you can go back to find which firmware was deployed to what miners and when it was deployed. The deployment process in the new manager is async and no longer blocks you from using the rest of the app. Simply close and come back later to see progress/result.

Step 1. Pick how you want to deploy
<img width="1904" height="1002" alt="Screenshot 2025-11-16 at 9 22 02 AM" src="https://github.com/user-attachments/assets/d56d0f46-80db-4b63-9c4f-30e6f8ab8731" />

Step 2. Pick from the miners compatible with the selected firmware
<img width="1904" height="1002" alt="Screenshot 2025-11-16 at 9 22 14 AM" src="https://github.com/user-attachments/assets/2302ceee-ce29-43cf-bf14-6bb2add41a49" />

Step 3. Review
<img width="1904" height="1002" alt="Screenshot 2025-11-16 at 9 22 19 AM" src="https://github.com/user-attachments/assets/780e53f5-aa36-46ed-9993-e4ab082c4ae4" />

Step 3. Roll it out!
<img width="1205" height="869" alt="Screenshot 2025-11-16 at 9 24 16 AM" src="https://github.com/user-attachments/assets/e17c2932-c13c-4008-97b7-d6c50d2e978c" />
<img width="1205" height="869" alt="Screenshot 2025-11-16 at 9 26 03 AM" src="https://github.com/user-attachments/assets/ad2c0aed-5e96-4923-aa6d-d44d9a600551" />


### Firmware deployments (old)
Step 1. Pick how you want to deploy
<img width="1922" height="1192" alt="Screenshot 2025-08-15 at 10 54 21 PM" src="https://github.com/user-attachments/assets/d2a8d55e-22dd-4a84-b1fa-1cfe66ecaa49" />

Step 2. Pick the miners compatible with the selected firmware
<img width="1922" height="1192" alt="Screenshot 2025-08-15 at 10 54 31 PM" src="https://github.com/user-attachments/assets/06582d71-d846-4fff-a39d-2342589da24b" />

Step 3. Roll it out!
<img width="1922" height="1192" alt="Screenshot 2025-08-15 at 10 56 41 PM" src="https://github.com/user-attachments/assets/9f271416-d969-40ad-9a91-2321c1650e01" />
<img width="1922" height="1192" alt="Screenshot 2025-08-15 at 10 57 58 PM" src="https://github.com/user-attachments/assets/33eefe58-f943-41ad-b253-adbafaa0cc03" />


### Miner Watch Dog
Allow watch dog to monitor your miners for indicators that it has stopped hashing or for some reason power usage dropped indicating an error. In these scenarios watch dog will issue a restart request to the miner to get it back up and hashing while you're not watching. Open the watch dog actions log to check what actions have happened while you were away. You can configure which miners are monitored by watch dog in settings.

<img width="837" height="764" alt="Screenshot 2025-09-14 at 7 59 55 PM" src="https://github.com/user-attachments/assets/dbfb5192-9218-4f17-ab2b-465a39fd1149" />


### HashRipper Settings
Configured general miner polling intervals for the app
<img width="912" height="700" alt="Screenshot 2025-09-08 at 8 13 03 PM" src="https://github.com/user-attachments/assets/6abbc208-b27c-4234-a042-5f0f072c06ff" />

Configure subnets to make the miner swarm scan miners that are only visibily via Tailscale vpn subnets
<img width="912" height="700" alt="Screenshot 2025-09-22 at 9 35 50 PM" src="https://github.com/user-attachments/assets/41777788-3d00-4a80-8bf6-5a871120484c" />


Configure watch dog and what miners are monitored
<img width="912" height="700" alt="Screenshot 2025-09-08 at 8 12 59 PM" src="https://github.com/user-attachments/assets/cc274c26-c0b9-479f-ac62-d8713eea911b" />

### Status Bar Overview

Aggregated miner stats in a status bar view.

<img width="352" height="461" alt="Screenshot 2025-10-11 at 12 07 24 PM" src="https://github.com/user-attachments/assets/02c816b4-8688-455b-ba71-2ab8b882378f" />

#Building the app from Source

At some point I'll build a release binary but until then if you want to give it a go

## Building the app
- Download Xcode 26 from Apple or macOS app store
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




