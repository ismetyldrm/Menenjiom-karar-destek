using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace MenengiomaBackend.Migrations
{
    /// <inheritdoc />
    public partial class AddSeriesFilesTable : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "SeriesFiles",
                columns: table => new
                {
                    SeriesID = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    StudyID = table.Column<int>(type: "integer", nullable: false),
                    FilePath_Original = table.Column<string>(type: "text", nullable: false),
                    FilePath_Mask = table.Column<string>(type: "text", nullable: false),
                    TumorVolume = table.Column<float>(type: "real", nullable: false),
                    IsProcessed = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SeriesFiles", x => x.SeriesID);
                    table.ForeignKey(
                        name: "FK_SeriesFiles_Studies_StudyID",
                        column: x => x.StudyID,
                        principalTable: "Studies",
                        principalColumn: "StudyID",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_SeriesFiles_StudyID",
                table: "SeriesFiles",
                column: "StudyID");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "SeriesFiles");
        }
    }
}
