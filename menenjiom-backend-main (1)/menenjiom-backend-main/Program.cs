using MenengiomaBackend.Data;
using Microsoft.EntityFrameworkCore;
using MenengiomaBackend.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Text;
using MenengiomaBackend.Models; // User modeline erişebilmek için

var builder = WebApplication.CreateBuilder(args);

// CORS politikasını ekliyoruz
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll",
        builder =>
        {
            builder.AllowAnyOrigin()
                   .AllowAnyMethod()
                   .AllowAnyHeader();
        });
});

// 1. PostgreSQL Veritabanı Bağlantımız
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// --- JWT YAPILANDIRMASI ---
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidAudience = builder.Configuration["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Key"]))
        };
    });

builder.Services.AddScoped<TokenService>(); // Token servisini sisteme tanıtıyoruz
// ------------------------------------------

// 2. Projeye Controller kullanacağımızı söylüyoruz
builder.Services.AddControllers();

// Yapay Zeka servisini sisteme tanıtıyoruz ve uzun süren analizler için zaman aşımı süresini uzatıyoruz
builder.Services.AddHttpClient<AiIntegrationService>(client =>
{
    client.Timeout = TimeSpan.FromMinutes(10);
});

// YENİ EKLENEN SATIR: Şifre sıfırlama için Email Servisini sisteme tanıtıyoruz
builder.Services.AddScoped<EmailService>();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Uygulamaya CORS politikasını kullan diyoruz
app.UseCors("AllowAll");

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthentication(); // Önce kimlik doğrula
app.UseAuthorization();  // Sonra yetkiyi kontrol et
app.MapControllers();

// --- KESİN ÇÖZÜM: ADMİN ŞİFRESİNİ "admin123" OLARAK GÜNCELLEME VE TOHUMLAMA ---
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    try
    {
        var context = services.GetRequiredService<AppDbContext>();

        // Veritabanında "admin" kullanıcı adına sahip bir hesap var mı kontrol et
        var existingAdmin = context.Users.FirstOrDefault(u => u.Username == "admin");

        if (existingAdmin == null)
        {
            // Eğer hiç yoksa, tamamen küçük harflerle admin123 olarak sıfırdan oluşturuyoruz
            var defaultAdmin = new User
            {
                Username = "admin",
                FullName = "Sistem Yöneticisi",
                Email = "admin@hastane.com",
                Role = "Admin",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword("admin123")
            };

            context.Users.Add(defaultAdmin);
            context.SaveChanges();
            Console.WriteLine("\n[SİSTEM] --> İlk Admin hesabı sıfırdan oluşturuldu! (Şifre: admin123)\n");
        }
        else
        {
            // EĞER VARSA: Eski hatalı şifreyi ezmek için şifresini ve rolünü kesin olarak admin123 yapıyoruz
            existingAdmin.PasswordHash = BCrypt.Net.BCrypt.HashPassword("admin123");
            existingAdmin.Role = "Admin";
            context.SaveChanges();
            Console.WriteLine("\n[SİSTEM] --> Mevcut admin hesabının şifresi kesin olarak 'admin123' yapıldı!\n");
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"\n[SİSTEM HATASI] --> Admin güncellenirken hata oluştu: {ex.Message}\n");
    }
}
// -----------------------------------------------------------------------------

app.Run();