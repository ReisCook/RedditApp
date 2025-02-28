# RedditApp


# How to Set Up the Reddit App

Follow these step-by-step instructions to set up and run the Reddit app:

## 1. Create a New Xcode Project

1. Open Xcode and select "Create a new Xcode project"
2. Choose "App" as the template under iOS
3. Enter your project details:
   - Name: "RedditClone" (or your preferred name)
   - Interface: "SwiftUI"
   - Language: "Swift"
   - Click "Next" and choose where to save the project

## 2. Set Up Reddit API Credentials

1. Go to [Reddit's App Preferences](https://www.reddit.com/prefs/apps)
2. Scroll down and click "create app" or "create another app"
3. Fill in the details:
   - Name: "RedditClone" (or your preferred name)
   - App type: Select "installed app"
   - Description: "Reddit client app"
   - About URL: (can leave blank)
   - Redirect URI: Enter `redditclone://auth`
   - Click "create app"
4. After creation, note your:
   - Client ID (appears under your app name)
   - Secret (optional for installed apps)

## 3. Add Dependencies

### Option A: Using Swift Package Manager (Recommended)

1. In Xcode, go to File → Swift Packages → Add Package Dependency
2. Enter package URL: `https://github.com/onevcat/Kingfisher.git`
3. Click "Next" and select the version (latest stable, typically)
4. Click "Finish"

### Option B: Using CocoaPods

1. Close Xcode
2. Install CocoaPods if you haven't already: `sudo gem install cocoapods`
3. Navigate to your project directory in Terminal
4. Create a Podfile: `pod init`
5. Edit the Podfile and add:
   ```ruby
   pod 'Kingfisher', '~> 7.0'
   ```
6. Install the pods: `pod install`
7. Open the newly created `.xcworkspace` file instead of the `.xcodeproj`

## 4. Configure URL Scheme for Authentication

1. In Xcode, select your project in the Navigator
2. Select your app target and go to the "Info" tab
3. Expand "URL Types"
4. Click the "+" button to add a new URL type
5. Fill in:
   - Identifier: `com.yourname.RedditClone` (or similar)
   - URL Schemes: `redditclone`
6. Save your changes

## 5. Replace the Default Code

In the code, replace `"YOUR_CLIENT_ID"` with the actual client ID you got from Reddit

## 6. Update Info.plist (if not done via URL Types UI)

If you prefer to edit the Info.plist directly, add:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>redditclone</string>
    </array>
  </dict>
</array>
```

## 7. Configure App Permissions (optional for better experience)

For optimal performance with media, add these to your Info.plist:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

## 8. Build and Run the App

1. Select your simulator or connected device
2. Click the "Run" button or press Cmd+R
3. When the app launches, you'll see the login screen
4. Tap "Login with Reddit" and complete the authentication in the web view
5. After successful login, you'll be redirected to the main app interface

## Troubleshooting Common Issues

- **Authentication fails**: Verify your Client ID and redirect URI match exactly what's in your Reddit app settings
- **Compiler errors**: Make sure Kingfisher is properly imported and check for any syntax errors
- **Media doesn't load**: Check that you've added the NSAppTransportSecurity settings to your Info.plist
- **App crashes on launch**: Ensure all required files are properly included in your project

