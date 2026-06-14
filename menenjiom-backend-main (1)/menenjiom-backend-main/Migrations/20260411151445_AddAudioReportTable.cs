using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace MenengiomaBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddAudioReportTable : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "AudioReports",
                columns: table => new
                {
                    AudioID = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    SeriesID = table.Column<int>(type: "integer", nullable: false),
                    DoctorVoiceData = table.Column<byte[]>(type: "bytea", nullable: true),
                    TtsVoiceData = table.Column<byte[]>(type: "bytea", nullable: true),
                    AudioFormat = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AudioReports", x => x.AudioID);
                    table.ForeignKey(
                        name: "FK_AudioReports_SeriesFiles_SeriesID",
                        column: x => x.SeriesID,
                        principalTable: "SeriesFiles",
                        principalColumn: "SeriesID",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AudioReports_SeriesID",
                table: "AudioReports",
                column: "SeriesID");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AudioReports");
        }
    }
}
