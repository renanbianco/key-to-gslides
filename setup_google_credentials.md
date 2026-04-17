# Setting up Google API Credentials

You need a **Google Cloud OAuth 2.0 client secret** to allow the app to upload files to your Google Drive.

## Steps

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or select an existing one)
3. Enable the **Google Drive API**:
   - Navigation menu → APIs & Services → Library
   - Search "Google Drive API" → Enable
4. Create OAuth credentials:
   - Navigation menu → APIs & Services → Credentials
   - Click **Create Credentials** → **OAuth client ID**
   - Application type: **Desktop app**
   - Name it anything (e.g. "Keynote Converter")
   - Click **Create**
5. Download the JSON file:
   - Click the download icon next to your new credential
   - Rename the downloaded file to **`client_secret.json`**
   - Move it to the `credentials/` folder in this project
6. Configure the OAuth consent screen:
   - Navigation menu → APIs & Services → OAuth consent screen
   - Choose **External** (unless you have a Google Workspace)
   - Fill in app name, support email
   - Add your Google account as a **Test user**
   - Save

## First Run

On the first conversion, your browser will open asking you to authorise the app.
Accept, and the token will be saved to `credentials/token.json` for future runs.

## File structure after setup

```
credentials/
├── client_secret.json   ← you place this here
└── token.json           ← auto-created on first auth
```
