using System.Text;
using Amazon.Lambda.Core;
using Amazon.Lambda.S3Events;
using Amazon.S3;
using Amazon.S3.Model;

// Configure Lambda serializer
[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace CsvToJsonLambda
{
    public class Function
    {
        private readonly IAmazonS3 _s3Client;
        private const string Delimiter = ",";

        public Function() : this(new AmazonS3Client()) { }

        public Function(IAmazonS3 s3Client)
        {
            _s3Client = s3Client;
        }

        private async Task<string> GetLatestOutputBucketAsync()
        {
            var bucketsResponse = await _s3Client.ListBucketsAsync();
            return bucketsResponse.Buckets
                .Where(b => b.BucketName.StartsWith("csv-to-json-output-"))
                .OrderByDescending(b => b.CreationDate)
                .FirstOrDefault()?.BucketName;
        }

        public async Task FunctionHandler(S3Event s3Event, ILambdaContext context)
        {
            context.Logger.LogLine("Lambda function invoked.");

            if (s3Event.Records.FirstOrDefault() is not { } record)
            {
                context.Logger.LogLine("No S3 event records found.");
                return;
            }

            var bucketName = record.S3.Bucket.Name;
            var objectKey = record.S3.Object.Key;

            if (!objectKey.EndsWith(".csv", StringComparison.OrdinalIgnoreCase))
            {
                context.Logger.LogLine("Unsupported file format. Only .csv files are processed.");
                return;
            }

            try
            {
                var outputBucket = await GetLatestOutputBucketAsync();
                if (outputBucket == null)
                {
                    context.Logger.LogLine("No suitable output bucket found.");
                    return;
                }

                context.Logger.LogLine($"Processing file '{objectKey}' from bucket '{bucketName}'.");

                var response = await _s3Client.GetObjectAsync(bucketName, objectKey);
                string csvContent;
                using (var reader = new StreamReader(response.ResponseStream))
                {
                    csvContent = await reader.ReadToEndAsync();
                }

                if (!csvContent.Contains(Delimiter))
                {
                    context.Logger.LogLine("The uploaded file does not appear to be a valid CSV file.");
                    return;
                }

                var jsonContent = ConvertCsvToJson(csvContent);
                var jsonKey = Path.ChangeExtension(objectKey, ".json");

                using var jsonStream = new MemoryStream(Encoding.UTF8.GetBytes(jsonContent));
                var putRequest = new PutObjectRequest
                {
                    BucketName = outputBucket,
                    Key = jsonKey,
                    InputStream = jsonStream,
                    ContentType = "application/json"
                };

                await _s3Client.PutObjectAsync(putRequest);
                context.Logger.LogLine($"Successfully converted '{objectKey}' to JSON and uploaded to '{outputBucket}/{jsonKey}'.");
            }
            catch (Exception ex)
            {
                context.Logger.LogLine($"Error processing file: {ex.Message}");
                throw;
            }
        }

        private string ConvertCsvToJson(string csvContent)
        {
            var lines = csvContent.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
            var headers = lines.First().Split(Delimiter);

            var jsonBuilder = new StringBuilder();
            jsonBuilder.AppendLine("[");

            foreach (var line in lines.Skip(1))
            {
                var values = line.Split(Delimiter);
                if (values.Length != headers.Length)
                {
                    throw new InvalidOperationException("CSV row does not match header column count.");
                }

                jsonBuilder.AppendLine("    {");

                for (int i = 0; i < headers.Length; i++)
                {
                    jsonBuilder.AppendFormat("        \"{0}\": \"{1}\"{2}\n",
                        headers[i].Trim(),
                        values[i].Trim(),
                        i < headers.Length - 1 ? "," : string.Empty);
                }

                jsonBuilder.AppendLine("    },");
            }

            if (jsonBuilder.Length > 2)
            {
                jsonBuilder.Length -= 3; // Remove trailing comma and newline
            }

            jsonBuilder.AppendLine("\n]");
            return jsonBuilder.ToString();
        }
    }
}
