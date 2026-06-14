using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MenengiomaBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddAiReportContentToSeriesFile : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AiReportContent",
                table: "SeriesFiles",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "AiReportContent",
                table: "SeriesFiles");
        }
    }
}
