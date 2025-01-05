#!/bin/bash

set -e

# Konfiguration
TEST_FILE="test.csv"
OUTPUT_FILE="test.json"
WAIT_TIME=10

# Farben definieren
COLOR_GREEN='\033[0;32m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# Delimiter-Abfrage
echo -e "${COLOR_GREEN}Did you change the Delimiter variable in Function.cs? If yes, enter it now (press Enter for default ','):${COLOR_RESET}"
read -r DELIMITER
DELIMITER=${DELIMITER:-,}

echo -e "${COLOR_GREEN}Using delimiter: '$DELIMITER'${COLOR_RESET}"

# Alte Testdateien bereinigen
echo -e "${COLOR_BLUE}Cleaning up existing test files...${COLOR_RESET}"
rm -f "$TEST_FILE" "$OUTPUT_FILE"

# S3-Buckets ermitteln
IN_BUCKET_NAME=$(aws s3 ls | grep "m346-csv-to-json-input-" | tail -n 1 | awk '{print $3}')
OUT_BUCKET_NAME=$(aws s3 ls | grep "m346-csv-to-json-output-" | tail -n 1 | awk '{print $3}')

if [ -z "$IN_BUCKET_NAME" ] || [ -z "$OUT_BUCKET_NAME" ]; then
    echo "Error: Could not find input or output buckets. Please run init.sh first."
    exit 1
fi

echo -e "${COLOR_GREEN}Using Input Bucket: $IN_BUCKET_NAME${COLOR_RESET}"
echo -e "${COLOR_GREEN}Using Output Bucket: $OUT_BUCKET_NAME${COLOR_RESET}"
echo -e "${COLOR_GREEN}Using Delimiter: $DELIMITER${COLOR_RESET}"

# Test-CSV erstellen
echo "id${DELIMITER}name${DELIMITER}age${DELIMITER}city${DELIMITER}occupation
1${DELIMITER}John${DELIMITER}25${DELIMITER}New York${DELIMITER}Engineer
2${DELIMITER}Jane${DELIMITER}30${DELIMITER}San Francisco${DELIMITER}Designer
3${DELIMITER}Bob${DELIMITER}45${DELIMITER}Chicago${DELIMITER}Manager" > "$TEST_FILE"

echo -e "\n${COLOR_BLUE}Input CSV file contents:${COLOR_RESET}"
echo "------------------------"
cat "$TEST_FILE"
echo "------------------------"

# Test-CSV hochladen
echo -e "\n${COLOR_BLUE}Uploading test CSV file to S3...${COLOR_RESET}"
aws s3 cp "$TEST_FILE" "s3://$IN_BUCKET_NAME/"

# Warten auf Konvertierung
echo -e "${COLOR_BLUE}Waiting for conversion (${WAIT_TIME} seconds)...${COLOR_RESET}"
sleep "$WAIT_TIME"

# Konvertierte JSON-Datei herunterladen
echo -e "\n${COLOR_BLUE}Downloading converted JSON file...${COLOR_RESET}"
aws s3 cp "s3://$OUT_BUCKET_NAME/$OUTPUT_FILE" .

echo -e "\n${COLOR_BLUE}Output JSON file contents:${COLOR_RESET}"
echo "------------------------"
cat "$OUTPUT_FILE"
echo "------------------------"

# Zusammenfassung
echo -e "\n${COLOR_GREEN}Test completed successfully!${COLOR_RESET}"
echo -e "\n${COLOR_BLUE}Summary:${COLOR_RESET}"
echo "Input file: $TEST_FILE"
echo "Output file: $OUTPUT_FILE"
echo "Delimiter: $DELIMITER"

echo -e "\n${COLOR_BLUE}Component Names:${COLOR_RESET}"
echo "Input Bucket: $IN_BUCKET_NAME"
echo "Output Bucket: $OUT_BUCKET_NAME"
echo "Lambda Function: CsvToJsonFunction"
