#!/bin/bash

set -e

# Farben definieren
COLOR_GREEN='\033[0;32m'
COLOR_BLUE='\033[0;34m'
COLOR_YELLOW='\033[1;33m'
COLOR_RESET='\033[0m'

# Hinweis zur Anpassung des Delimiters
printf "${COLOR_YELLOW}To change the delimiter (default ',') go to the Function.cs code and change the Delimiter variable${COLOR_RESET}\n"
printf "${COLOR_YELLOW}After changing and saving the new delimiter or to continue with the default one press enter to continue...${COLOR_RESET}"
read -r

# Variablen initialisieren
AWS_REGION="us-east-1"
FUNCTION_NAME="CsvToJsonFunction"
CURRENT_TIME=$(date +%Y%m%d%H%M%S)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
INPUT_BUCKET="m346-csv-to-json-input-${CURRENT_TIME}"
OUTPUT_BUCKET="m346-csv-to-json-output-${CURRENT_TIME}"
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/LabRole"

# Konfiguration anzeigen
echo -e "\n${COLOR_BLUE}Configuration:${COLOR_RESET}"
cat <<EOF
AWS Region: $AWS_REGION
AWS Account ID: $ACCOUNT_ID
Input Bucket: $INPUT_BUCKET
Output Bucket: $OUTPUT_BUCKET
Lambda Function: $FUNCTION_NAME
EOF

# Bestehende Ressourcen bereinigen
echo -e "\n${COLOR_BLUE}Cleaning up existing resources...${COLOR_RESET}"
aws lambda delete-function --function-name "$FUNCTION_NAME" 2>/dev/null || true

LAST_INPUT=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `m346-csv-to-json-input-`) == `true`].Name' --output text | tr '\t' '\n' | sort | tail -n 1)
LAST_OUTPUT=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `m346-csv-to-json-output-`) == `true`].Name' --output text | tr '\t' '\n' | sort | tail -n 1)

if [ -n "$LAST_INPUT" ]; then
    echo "Removing previous input bucket: $LAST_INPUT"
    aws s3 rm "s3://$LAST_INPUT" --recursive
    aws s3api delete-bucket --bucket "$LAST_INPUT"
fi

if [ -n "$LAST_OUTPUT" ]; then
    echo "Removing previous output bucket: $LAST_OUTPUT"
    aws s3 rm "s3://$LAST_OUTPUT" --recursive
    aws s3api delete-bucket --bucket "$LAST_OUTPUT"
fi

# Neue S3-Buckets erstellen
echo -e "\n${COLOR_BLUE}Creating S3 buckets...${COLOR_RESET}"
aws s3api create-bucket --bucket "$INPUT_BUCKET" --region "$AWS_REGION"
aws s3api create-bucket --bucket "$OUTPUT_BUCKET" --region "$AWS_REGION"
echo -e "${COLOR_GREEN}Buckets created successfully${COLOR_RESET}"

# Lambda-Funktion bereitstellen
echo -e "\n${COLOR_BLUE}Deploying Lambda function...${COLOR_RESET}"
cd ..
cd src/M346-Projekt-CsvToJson
dotnet lambda deploy-function "$FUNCTION_NAME" --function-role "$ROLE_ARN"

# Lambda-Berechtigungen konfigurieren
echo -e "\n${COLOR_BLUE}Configuring Lambda permissions...${COLOR_RESET}"
aws lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --statement-id S3InvokeFunction \
    --action lambda:InvokeFunction \
    --principal s3.amazonaws.com \
    --source-arn "arn:aws:s3:::$INPUT_BUCKET"

# S3-Trigger einrichten
echo -e "\n${COLOR_BLUE}Setting up S3 trigger...${COLOR_RESET}"
NOTIFICATION_CONFIG=$(cat <<EOM
{
    "LambdaFunctionConfigurations": [
        {
            "LambdaFunctionArn": "arn:aws:lambda:$AWS_REGION:$ACCOUNT_ID:function:$FUNCTION_NAME",
            "Events": ["s3:ObjectCreated:*"]
        }
    ]
}
EOM
)
aws s3api put-bucket-notification-configuration \
    --bucket "$INPUT_BUCKET" \
    --notification-configuration "$NOTIFICATION_CONFIG"

# Abschlussmeldung
echo -e "\n${COLOR_GREEN}Setup completed successfully!${COLOR_RESET}"
cat <<EOF

${COLOR_BLUE}Component Names:${COLOR_RESET}
Input Bucket: $INPUT_BUCKET
Output Bucket: $OUTPUT_BUCKET
Lambda Function: $FUNCTION_NAME
EOF
