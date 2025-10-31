set -e  # Exit the script if any command fails

# Helper function to update fields in the config JSON using jq
function update_json() {
  local input_file=$1
  local jq_filter=$2
  local tmp_file
  tmp_file=$(mktemp)

  jq "$jq_filter" "$input_file" > "$tmp_file" && mv "$tmp_file" "$input_file"
}

# Create a Django superuser usingenvironment variables for email and password
DJANGO_SUPERUSER_PASSWORD=$ADMIN_PASSWORD python manage.py createsuperuser --email $ADMIN_USER_EMAIL --username admin --noinput;

# Check if MSAL configuration is present
if [ -n "$MSAL_AUTH_REDIRECT_URI" ]; then
  echo "MSAL configuration detected, M365 Search Providers will be enabled"

  # Enable Microsoft 365 search providers in the preloaded configuration
  PROVIDERS_FILE="/app/SearchProviders/preloaded.json"
  update_json "$PROVIDERS_FILE" 'map(if .name == "Outlook Messages - Microsoft 365" then .active = true else . end)'
  update_json "$PROVIDERS_FILE" 'map(if .name == "Calendar Events - Microsoft 365" then .active = true else . end)'
  update_json "$PROVIDERS_FILE" 'map(if .name == "OneDrive Files - Microsoft 365" then .active = true else . end)'
  update_json "$PROVIDERS_FILE" 'map(if .name == "SharePoint Sites - Microsoft 365" then .active = true else . end)'
  update_json "$PROVIDERS_FILE" 'map(if .name == "Teams Chat - Microsoft 365" then .active = true else . end)'

  # If the Microsoft client secret is provided, enable MSAL authentication
  if [ -n "$MICROSOFT_CLIENT_SECRET" ]; then
    echo "Microsoft client secret found — enabling MSAL authentication"

    AUTH_TARGET="/app/swirl/fixtures/DefaultAuthenticators.json"

    # Update authenticator config with values from environment variables
    update_json "$AUTH_TARGET" '.[0].fields.active = true'
    update_json "$AUTH_TARGET" '.[0].fields.client_id = "'"$MS_AUTH_CLIENT_ID"'"'
    update_json "$AUTH_TARGET" '.[0].fields.client_secret = "'"$MICROSOFT_CLIENT_SECRET"'"'
    update_json "$AUTH_TARGET" '.[0].fields.app_uri = "https://'"$SWIRL_FQDN"'"'
    update_json "$AUTH_TARGET" '.[0].fields.auth_uri = "'"$MSAL_AUTH_AUTHORITY"'"'
    update_json "$AUTH_TARGET" '.[0].fields.token_uri = "'"$OAUTH_CONFIG_TOKEN_ENDPOINT"'"'
  else
    echo "No MICROSOFT_CLIENT_SECRET configuration detected, Microsoft authentication for search providers will not be enabled"
  fi

else
  echo "No MSAL configuration detected, M365 Search Providers will not be enabled"
fi

# If Azure Government compatibility is enabled, adjust provider URLs accordingly
if [ "$AZ_GOV_COMPATIBLE" == "true" ]; then
  echo "Processing Search Providers for Azure Government"
  PROVIDERS_FILE="/app/SearchProviders/preloaded.json"
  tmp_file=$(mktemp)

  # Replace microsoft.com with microsoft.us for all entries
  sed 's/microsoft\.com/microsoft.us/g' "$PROVIDERS_FILE" > "$tmp_file" && mv "$tmp_file" "$PROVIDERS_FILE"
fi

# Load Swirl's initial data
python swirl.py load_data
python swirl.py reload_ai_prompts
python swirl.py load_branding