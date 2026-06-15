using System.Net.Http.Headers;
using System.Text.Json;
using MenengiomaBackend.DTOs;
using Microsoft.AspNetCore.Http;

namespace MenengiomaBackend.Services
{
    public class AiIntegrationService
    {
        private readonly HttpClient _httpClient;

        public AiIntegrationService(HttpClient httpClient)
        {
            _httpClient = httpClient;
            _httpClient.BaseAddress = new Uri("http://localhost:5000/");
            _httpClient.Timeout = TimeSpan.FromMinutes(10);
        }

        public async Task<AiAnalysisResultDto> AnalyzeMriAsync(IFormFile zipFile)
        {
            using var form = new MultipartFormDataContent();
            using var stream = zipFile.OpenReadStream();
            using var streamContent = new StreamContent(stream);

            streamContent.Headers.ContentType = MediaTypeHeaderValue.Parse(zipFile.ContentType ?? "application/zip");
            form.Add(streamContent, "file", zipFile.FileName);

            // Python'daki /api/analyze endpoint'ine dosyayı POST et
            var response = await _httpClient.PostAsync("api/analyze", form);

            if (!response.IsSuccessStatusCode)
            {
                var error = await response.Content.ReadAsStringAsync();
                throw new Exception($"Yapay zeka servisi hata verdi: {response.StatusCode} - {error}");
            }

            var jsonResponse = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<AiAnalysisResultDto>(jsonResponse,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

            return result;
        }
    }
}