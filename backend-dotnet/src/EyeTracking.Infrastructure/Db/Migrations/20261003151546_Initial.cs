using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EyeTracking.Infrastructure.Db.Migrations
{
    /// <inheritdoc />
    public partial class Initial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "access_log",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: true),
                    user_id = table.Column<int>(type: "int", nullable: false),
                    role = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    action = table.Column<string>(type: "nvarchar(40)", maxLength: 40, nullable: false),
                    detail = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_access_log", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "studies",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false),
                    retention_policy = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_studies", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "users",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    email = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    password_hash = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    role = table.Column<string>(type: "varchar(20)", unicode: false, maxLength: 20, nullable: false),
                    is_active = table.Column<bool>(type: "bit", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_users", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "ai_budgets",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    cost_cap_units = table.Column<double>(type: "float", nullable: false),
                    spent_units = table.Column<double>(type: "float", nullable: false),
                    send_free_text = table.Column<bool>(type: "bit", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ai_budgets", x => x.id);
                    table.ForeignKey(
                        name: "FK_ai_budgets_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "content_items",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    title = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    definition = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    topic_tags = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    face_id = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    voice_id = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    status = table.Column<string>(type: "varchar(20)", unicode: false, maxLength: 20, nullable: false),
                    text_reviewed = table.Column<bool>(type: "bit", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false),
                    updated_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_content_items", x => x.id);
                    table.ForeignKey(
                        name: "FK_content_items_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "debrief_forms",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    version = table.Column<int>(type: "int", nullable: false),
                    questions = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    enabled = table.Column<bool>(type: "bit", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_debrief_forms", x => x.id);
                    table.ForeignKey(
                        name: "FK_debrief_forms_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "demographics_forms",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    version = table.Column<int>(type: "int", nullable: false),
                    fields = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    published_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_demographics_forms", x => x.id);
                    table.ForeignKey(
                        name: "FK_demographics_forms_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "information_sheets",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    version = table.Column<int>(type: "int", nullable: false),
                    aims = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    discomfort_sources = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    benefits = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    data_handling = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    stop_rules = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    published_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_information_sheets", x => x.id);
                    table.ForeignKey(
                        name: "FK_information_sheets_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "measurement_settings",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    validation_min_correct = table.Column<double>(type: "float", nullable: false),
                    validation_max_uncertain = table.Column<double>(type: "float", nullable: false),
                    min_region_to_error_ratio = table.Column<double>(type: "float", nullable: false),
                    gaze_conf_threshold = table.Column<double>(type: "float", nullable: false),
                    calibration_points = table.Column<int>(type: "int", nullable: false),
                    allow_continue_without_validation = table.Column<bool>(type: "bit", nullable: false),
                    quality_max_uncertain_share = table.Column<double>(type: "float", nullable: false),
                    quality_max_missing_share = table.Column<double>(type: "float", nullable: false),
                    version = table.Column<int>(type: "int", nullable: false, defaultValue: 1)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_measurement_settings", x => x.id);
                    table.ForeignKey(
                        name: "FK_measurement_settings_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "protocols",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    name = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    definition = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    status = table.Column<string>(type: "varchar(20)", unicode: false, maxLength: 20, nullable: false),
                    version = table.Column<int>(type: "int", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false),
                    published_at = table.Column<DateTime>(type: "datetime2(6)", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_protocols", x => x.id);
                    table.ForeignKey(
                        name: "FK_protocols_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "settings_versions",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    version = table.Column<int>(type: "int", nullable: false),
                    values = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    rationale = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    changed_by = table.Column<int>(type: "int", nullable: true),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_settings_versions", x => x.id);
                    table.ForeignKey(
                        name: "FK_settings_versions_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "invitations",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    token = table.Column<string>(type: "nvarchar(64)", maxLength: 64, nullable: false, collation: "Latin1_General_100_BIN2"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    code = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false, collation: "Latin1_General_100_BIN2"),
                    created_by = table.Column<int>(type: "int", nullable: false),
                    expires_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false),
                    invitee_email = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: true),
                    used_at = table.Column<DateTime>(type: "datetime2(6)", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_invitations", x => x.id);
                    table.ForeignKey(
                        name: "FK_invitations_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_invitations_users_created_by",
                        column: x => x.created_by,
                        principalTable: "users",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "participants",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    code = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false, collation: "Latin1_General_100_BIN2"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    user_id = table.Column<int>(type: "int", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_participants", x => x.id);
                    table.ForeignKey(
                        name: "FK_participants_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_participants_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "study_memberships",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    user_id = table.Column<int>(type: "int", nullable: false),
                    study_role = table.Column<string>(type: "varchar(20)", unicode: false, maxLength: 20, nullable: false),
                    can_link_identity = table.Column<bool>(type: "bit", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_study_memberships", x => x.id);
                    table.ForeignKey(
                        name: "FK_study_memberships_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_study_memberships_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "content_media",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    content_id = table.Column<int>(type: "int", nullable: false),
                    key = table.Column<string>(type: "nvarchar(120)", maxLength: 120, nullable: false, collation: "Latin1_General_100_BIN2"),
                    path = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: false),
                    content_type = table.Column<string>(type: "nvarchar(60)", maxLength: 60, nullable: false),
                    size = table.Column<int>(type: "int", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_content_media", x => x.id);
                    table.ForeignKey(
                        name: "FK_content_media_content_items_content_id",
                        column: x => x.content_id,
                        principalTable: "content_items",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "generation_jobs",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    kind = table.Column<string>(type: "nvarchar(10)", maxLength: 10, nullable: false),
                    provider = table.Column<string>(type: "nvarchar(40)", maxLength: 40, nullable: false),
                    content_id = table.Column<int>(type: "int", nullable: false),
                    status = table.Column<string>(type: "nvarchar(12)", maxLength: 12, nullable: false),
                    assignment_id = table.Column<int>(type: "int", nullable: true),
                    segment_id = table.Column<string>(type: "nvarchar(60)", maxLength: 60, nullable: true),
                    attempts = table.Column<int>(type: "int", nullable: false),
                    max_attempts = table.Column<int>(type: "int", nullable: false),
                    cost_estimate_units = table.Column<double>(type: "float", nullable: false),
                    cost_actual_units = table.Column<double>(type: "float", nullable: false),
                    error = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    request = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    result = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false),
                    started_at = table.Column<DateTime>(type: "datetime2(6)", nullable: true),
                    finished_at = table.Column<DateTime>(type: "datetime2(6)", nullable: true),
                    next_attempt_at = table.Column<DateTime>(type: "datetime2(6)", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_generation_jobs", x => x.id);
                    table.ForeignKey(
                        name: "FK_generation_jobs_content_items_content_id",
                        column: x => x.content_id,
                        principalTable: "content_items",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_generation_jobs_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "assignments",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    participant_id = table.Column<int>(type: "int", nullable: false),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    protocol_id = table.Column<int>(type: "int", nullable: false),
                    order_index = table.Column<int>(type: "int", nullable: false),
                    status = table.Column<string>(type: "varchar(20)", unicode: false, maxLength: 20, nullable: false),
                    topic = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: true),
                    topic_free_text = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    content_id = table.Column<int>(type: "int", nullable: true),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_assignments", x => x.id);
                    table.ForeignKey(
                        name: "FK_assignments_content_items_content_id",
                        column: x => x.content_id,
                        principalTable: "content_items",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_assignments_participants_participant_id",
                        column: x => x.participant_id,
                        principalTable: "participants",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_assignments_protocols_protocol_id",
                        column: x => x.protocol_id,
                        principalTable: "protocols",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_assignments_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "consents",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    participant_id = table.Column<int>(type: "int", nullable: false),
                    sheet_version = table.Column<int>(type: "int", nullable: false),
                    participate = table.Column<bool>(type: "bit", nullable: false),
                    audio_recording = table.Column<bool>(type: "bit", nullable: false),
                    video_recording = table.Column<bool>(type: "bit", nullable: false),
                    given_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false),
                    withdrawn_at = table.Column<DateTime>(type: "datetime2(6)", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_consents", x => x.id);
                    table.ForeignKey(
                        name: "FK_consents_participants_participant_id",
                        column: x => x.participant_id,
                        principalTable: "participants",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "demographics_answers",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    participant_id = table.Column<int>(type: "int", nullable: false),
                    form_version = table.Column<int>(type: "int", nullable: false),
                    answers = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    updated_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_demographics_answers", x => x.id);
                    table.ForeignKey(
                        name: "FK_demographics_answers_participants_participant_id",
                        column: x => x.participant_id,
                        principalTable: "participants",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "profiles",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    participant_id = table.Column<int>(type: "int", nullable: false),
                    display_name = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    response_mode = table.Column<string>(type: "varchar(20)", unicode: false, maxLength: 20, nullable: false),
                    voice_preference = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    face_preference = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    speed = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    accessibility_needs = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    interests = table.Column<string>(type: "nvarchar(max)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_profiles", x => x.id);
                    table.ForeignKey(
                        name: "FK_profiles_participants_participant_id",
                        column: x => x.participant_id,
                        principalTable: "participants",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "sessions",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    participant_id = table.Column<int>(type: "int", nullable: false),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    device = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    screen = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    camera = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    gaze_model = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    synthetic = table.Column<bool>(type: "bit", nullable: false),
                    status = table.Column<string>(type: "varchar(20)", unicode: false, maxLength: 20, nullable: false),
                    calibration_valid = table.Column<bool>(type: "bit", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false),
                    ended_at = table.Column<DateTime>(type: "datetime2(6)", nullable: true),
                    end_reason = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: true),
                    notes = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    assignment_id = table.Column<int>(type: "int", nullable: true),
                    protocol_id = table.Column<int>(type: "int", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_sessions", x => x.id);
                    table.ForeignKey(
                        name: "FK_sessions_participants_participant_id",
                        column: x => x.participant_id,
                        principalTable: "participants",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_sessions_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "answers",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    segment_id = table.Column<string>(type: "nvarchar(60)", maxLength: 60, nullable: false),
                    question_id = table.Column<string>(type: "nvarchar(60)", maxLength: 60, nullable: false),
                    kind = table.Column<string>(type: "nvarchar(16)", maxLength: 16, nullable: false),
                    option = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    correct = table.Column<bool>(type: "bit", nullable: true),
                    t_ms = table.Column<int>(type: "int", nullable: false),
                    next_segment_id = table.Column<string>(type: "nvarchar(60)", maxLength: 60, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_answers", x => x.id);
                    table.ForeignKey(
                        name: "FK_answers_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "calibrations",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    @params = table.Column<string>(name: "params", type: "nvarchar(max)", nullable: false),
                    residual_px_median = table.Column<double>(type: "float", nullable: false),
                    residual_px_p90 = table.Column<double>(type: "float", nullable: false),
                    per_target = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    points = table.Column<int>(type: "int", nullable: false),
                    accepted = table.Column<bool>(type: "bit", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_calibrations", x => x.id);
                    table.ForeignKey(
                        name: "FK_calibrations_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "debrief_answers",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    participant_id = table.Column<int>(type: "int", nullable: false),
                    form_version = table.Column<int>(type: "int", nullable: false),
                    answers = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    skipped = table.Column<bool>(type: "bit", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_debrief_answers", x => x.id);
                    table.ForeignKey(
                        name: "FK_debrief_answers_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_debrief_answers_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "live_conversations",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    participant_id = table.Column<int>(type: "int", nullable: false),
                    topic = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    input_mode = table.Column<string>(type: "nvarchar(10)", maxLength: 10, nullable: false),
                    transcript_allowed = table.Column<bool>(type: "bit", nullable: false),
                    reply_provider = table.Column<string>(type: "nvarchar(40)", maxLength: 40, nullable: false),
                    avatar_provider = table.Column<string>(type: "nvarchar(40)", maxLength: 40, nullable: false),
                    stt_provider = table.Column<string>(type: "nvarchar(40)", maxLength: 40, nullable: false),
                    status = table.Column<string>(type: "varchar(20)", unicode: false, maxLength: 20, nullable: false),
                    turns_used = table.Column<int>(type: "int", nullable: false),
                    off_topic_streak = table.Column<int>(type: "int", nullable: false),
                    end_reason = table.Column<string>(type: "nvarchar(30)", maxLength: 30, nullable: true),
                    cost_units = table.Column<double>(type: "float", nullable: false),
                    started_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false),
                    ended_at = table.Column<DateTime>(type: "datetime2(6)", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_live_conversations", x => x.id);
                    table.ForeignKey(
                        name: "FK_live_conversations_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_live_conversations_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "observations",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    author_id = table.Column<int>(type: "int", nullable: false),
                    category = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    severity = table.Column<string>(type: "nvarchar(10)", maxLength: 10, nullable: false),
                    text = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    t_ms = table.Column<int>(type: "int", nullable: true),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_observations", x => x.id);
                    table.ForeignKey(
                        name: "FK_observations_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_observations_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "reference_recordings",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    study_id = table.Column<int>(type: "int", nullable: false),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    source = table.Column<string>(type: "nvarchar(120)", maxLength: 120, nullable: false),
                    uploaded_by = table.Column<int>(type: "int", nullable: false),
                    settings = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    sample_count = table.Column<int>(type: "int", nullable: false),
                    valid_count = table.Column<int>(type: "int", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_reference_recordings", x => x.id);
                    table.ForeignKey(
                        name: "FK_reference_recordings_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_reference_recordings_studies_study_id",
                        column: x => x.study_id,
                        principalTable: "studies",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "session_events",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    t_ms = table.Column<int>(type: "int", nullable: false),
                    type = table.Column<string>(type: "nvarchar(24)", maxLength: 24, nullable: false),
                    payload = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_session_events", x => x.id);
                    table.ForeignKey(
                        name: "FK_session_events_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "stage_results",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    stage_index = table.Column<int>(type: "int", nullable: false),
                    decision = table.Column<string>(type: "nvarchar(12)", maxLength: 12, nullable: false),
                    reason = table.Column<string>(type: "nvarchar(40)", maxLength: 40, nullable: false),
                    correct_ratio = table.Column<double>(type: "float", nullable: true),
                    invalid_share = table.Column<double>(type: "float", nullable: false),
                    comfort_value = table.Column<int>(type: "int", nullable: true),
                    trials = table.Column<int>(type: "int", nullable: false),
                    next_stage_index = table.Column<int>(type: "int", nullable: true),
                    last_trial_id = table.Column<int>(type: "int", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_stage_results", x => x.id);
                    table.ForeignKey(
                        name: "FK_stage_results_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "stimulus_layouts",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    segment = table.Column<string>(type: "nvarchar(12)", maxLength: 12, nullable: false),
                    layout = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    stage_index = table.Column<int>(type: "int", nullable: true),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_stimulus_layouts", x => x.id);
                    table.ForeignKey(
                        name: "FK_stimulus_layouts_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "trials",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    stage_index = table.Column<int>(type: "int", nullable: false),
                    trial_index = table.Column<int>(type: "int", nullable: false),
                    t_ms = table.Column<int>(type: "int", nullable: false),
                    number_shown = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    zone = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    position = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    face_level = table.Column<int>(type: "int", nullable: false),
                    response = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: true),
                    correct = table.Column<bool>(type: "bit", nullable: false),
                    response_ms = table.Column<int>(type: "int", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_trials", x => x.id);
                    table.ForeignKey(
                        name: "FK_trials_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "validations",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    calibration_id = table.Column<int>(type: "int", nullable: false),
                    layout = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    passed = table.Column<bool>(type: "bit", nullable: false),
                    correct_ratio = table.Column<double>(type: "float", nullable: false),
                    uncertain_ratio = table.Column<double>(type: "float", nullable: false),
                    size_ratio = table.Column<double>(type: "float", nullable: false),
                    reasons = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    targets = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false),
                    settings_version = table.Column<int>(type: "int", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_validations", x => x.id);
                    table.ForeignKey(
                        name: "FK_validations_calibrations_calibration_id",
                        column: x => x.calibration_id,
                        principalTable: "calibrations",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_validations_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "live_turns",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    conversation_id = table.Column<int>(type: "int", nullable: false),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    index = table.Column<int>(type: "int", nullable: false),
                    role = table.Column<string>(type: "nvarchar(12)", maxLength: 12, nullable: false),
                    text = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    chars = table.Column<int>(type: "int", nullable: false),
                    t_ms = table.Column<int>(type: "int", nullable: true),
                    flags = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    latency_ms = table.Column<int>(type: "int", nullable: true),
                    cost_units = table.Column<double>(type: "float", nullable: false),
                    created_at = table.Column<DateTime>(type: "datetime2(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_live_turns", x => x.id);
                    table.ForeignKey(
                        name: "FK_live_turns_live_conversations_conversation_id",
                        column: x => x.conversation_id,
                        principalTable: "live_conversations",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_live_turns_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "reference_samples",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    recording_id = table.Column<int>(type: "int", nullable: false),
                    t_ms = table.Column<int>(type: "int", nullable: false),
                    x = table.Column<double>(type: "float", nullable: true),
                    y = table.Column<double>(type: "float", nullable: true),
                    valid = table.Column<bool>(type: "bit", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_reference_samples", x => x.id);
                    table.ForeignKey(
                        name: "FK_reference_samples_reference_recordings_recording_id",
                        column: x => x.recording_id,
                        principalTable: "reference_recordings",
                        principalColumn: "id");
                });

            migrationBuilder.CreateTable(
                name: "gaze_samples",
                columns: table => new
                {
                    id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    session_id = table.Column<int>(type: "int", nullable: false),
                    t_ms = table.Column<int>(type: "int", nullable: false),
                    x = table.Column<double>(type: "float", nullable: true),
                    y = table.Column<double>(type: "float", nullable: true),
                    conf = table.Column<double>(type: "float", nullable: false),
                    valid = table.Column<bool>(type: "bit", nullable: false),
                    region = table.Column<string>(type: "nvarchar(12)", maxLength: 12, nullable: false),
                    segment = table.Column<string>(type: "nvarchar(12)", maxLength: 12, nullable: false),
                    layout_id = table.Column<int>(type: "int", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_gaze_samples", x => x.id);
                    table.ForeignKey(
                        name: "FK_gaze_samples_sessions_session_id",
                        column: x => x.session_id,
                        principalTable: "sessions",
                        principalColumn: "id");
                    table.ForeignKey(
                        name: "FK_gaze_samples_stimulus_layouts_layout_id",
                        column: x => x.layout_id,
                        principalTable: "stimulus_layouts",
                        principalColumn: "id");
                });

            migrationBuilder.CreateIndex(
                name: "ix_access_log_study",
                table: "access_log",
                columns: new[] { "study_id", "created_at" });

            migrationBuilder.CreateIndex(
                name: "IX_ai_budgets_study_id",
                table: "ai_budgets",
                column: "study_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_answers_session_id",
                table: "answers",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_assignments_content_id",
                table: "assignments",
                column: "content_id");

            migrationBuilder.CreateIndex(
                name: "IX_assignments_participant_id",
                table: "assignments",
                column: "participant_id");

            migrationBuilder.CreateIndex(
                name: "IX_assignments_protocol_id",
                table: "assignments",
                column: "protocol_id");

            migrationBuilder.CreateIndex(
                name: "IX_assignments_study_id",
                table: "assignments",
                column: "study_id");

            migrationBuilder.CreateIndex(
                name: "IX_calibrations_session_id",
                table: "calibrations",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_consents_participant_id",
                table: "consents",
                column: "participant_id");

            migrationBuilder.CreateIndex(
                name: "IX_content_items_study_id",
                table: "content_items",
                column: "study_id");

            migrationBuilder.CreateIndex(
                name: "uq_media_key",
                table: "content_media",
                columns: new[] { "content_id", "key" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_debrief_answers_session_id",
                table: "debrief_answers",
                column: "session_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_debrief_answers_study_id",
                table: "debrief_answers",
                column: "study_id");

            migrationBuilder.CreateIndex(
                name: "uq_debrief_forms_study_version",
                table: "debrief_forms",
                columns: new[] { "study_id", "version" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_demographics_answers_participant_id",
                table: "demographics_answers",
                column: "participant_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "uq_form_version",
                table: "demographics_forms",
                columns: new[] { "study_id", "version" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_gaze_samples_layout_id",
                table: "gaze_samples",
                column: "layout_id");

            migrationBuilder.CreateIndex(
                name: "ix_gaze_samples_session_t",
                table: "gaze_samples",
                columns: new[] { "session_id", "t_ms" });

            migrationBuilder.CreateIndex(
                name: "IX_generation_jobs_content_id",
                table: "generation_jobs",
                column: "content_id");

            migrationBuilder.CreateIndex(
                name: "ix_generation_jobs_study_status",
                table: "generation_jobs",
                columns: new[] { "study_id", "status" });

            migrationBuilder.CreateIndex(
                name: "uq_sheet_version",
                table: "information_sheets",
                columns: new[] { "study_id", "version" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_invitations_created_by",
                table: "invitations",
                column: "created_by");

            migrationBuilder.CreateIndex(
                name: "IX_invitations_token",
                table: "invitations",
                column: "token",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "uq_invitation_code",
                table: "invitations",
                columns: new[] { "study_id", "code" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_live_conversations_session_id",
                table: "live_conversations",
                column: "session_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_live_conversations_study_id",
                table: "live_conversations",
                column: "study_id");

            migrationBuilder.CreateIndex(
                name: "ix_live_turns_conversation",
                table: "live_turns",
                columns: new[] { "conversation_id", "index" });

            migrationBuilder.CreateIndex(
                name: "IX_live_turns_session_id",
                table: "live_turns",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_measurement_settings_study_id",
                table: "measurement_settings",
                column: "study_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_observations_session",
                table: "observations",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_observations_study_id",
                table: "observations",
                column: "study_id");

            migrationBuilder.CreateIndex(
                name: "IX_participants_user_id",
                table: "participants",
                column: "user_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "uq_participant_code",
                table: "participants",
                columns: new[] { "study_id", "code" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_profiles_participant_id",
                table: "profiles",
                column: "participant_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_protocols_study_id",
                table: "protocols",
                column: "study_id");

            migrationBuilder.CreateIndex(
                name: "IX_reference_recordings_session_id",
                table: "reference_recordings",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_reference_recordings_study_id",
                table: "reference_recordings",
                column: "study_id");

            migrationBuilder.CreateIndex(
                name: "ix_reference_samples_recording_t",
                table: "reference_samples",
                columns: new[] { "recording_id", "t_ms" });

            migrationBuilder.CreateIndex(
                name: "IX_session_events_session_id",
                table: "session_events",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_sessions_participant_id",
                table: "sessions",
                column: "participant_id");

            migrationBuilder.CreateIndex(
                name: "IX_sessions_study_id",
                table: "sessions",
                column: "study_id");

            migrationBuilder.CreateIndex(
                name: "uq_settings_versions_study_version",
                table: "settings_versions",
                columns: new[] { "study_id", "version" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_stage_results_session_id",
                table: "stage_results",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_stimulus_layouts_session_id",
                table: "stimulus_layouts",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_study_memberships_user_id",
                table: "study_memberships",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "uq_membership",
                table: "study_memberships",
                columns: new[] { "study_id", "user_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_trials_session_id",
                table: "trials",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "IX_users_email",
                table: "users",
                column: "email",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_validations_calibration_id",
                table: "validations",
                column: "calibration_id");

            migrationBuilder.CreateIndex(
                name: "IX_validations_session_id",
                table: "validations",
                column: "session_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "access_log");

            migrationBuilder.DropTable(
                name: "ai_budgets");

            migrationBuilder.DropTable(
                name: "answers");

            migrationBuilder.DropTable(
                name: "assignments");

            migrationBuilder.DropTable(
                name: "consents");

            migrationBuilder.DropTable(
                name: "content_media");

            migrationBuilder.DropTable(
                name: "debrief_answers");

            migrationBuilder.DropTable(
                name: "debrief_forms");

            migrationBuilder.DropTable(
                name: "demographics_answers");

            migrationBuilder.DropTable(
                name: "demographics_forms");

            migrationBuilder.DropTable(
                name: "gaze_samples");

            migrationBuilder.DropTable(
                name: "generation_jobs");

            migrationBuilder.DropTable(
                name: "information_sheets");

            migrationBuilder.DropTable(
                name: "invitations");

            migrationBuilder.DropTable(
                name: "live_turns");

            migrationBuilder.DropTable(
                name: "measurement_settings");

            migrationBuilder.DropTable(
                name: "observations");

            migrationBuilder.DropTable(
                name: "profiles");

            migrationBuilder.DropTable(
                name: "reference_samples");

            migrationBuilder.DropTable(
                name: "session_events");

            migrationBuilder.DropTable(
                name: "settings_versions");

            migrationBuilder.DropTable(
                name: "stage_results");

            migrationBuilder.DropTable(
                name: "study_memberships");

            migrationBuilder.DropTable(
                name: "trials");

            migrationBuilder.DropTable(
                name: "validations");

            migrationBuilder.DropTable(
                name: "protocols");

            migrationBuilder.DropTable(
                name: "stimulus_layouts");

            migrationBuilder.DropTable(
                name: "content_items");

            migrationBuilder.DropTable(
                name: "live_conversations");

            migrationBuilder.DropTable(
                name: "reference_recordings");

            migrationBuilder.DropTable(
                name: "calibrations");

            migrationBuilder.DropTable(
                name: "sessions");

            migrationBuilder.DropTable(
                name: "participants");

            migrationBuilder.DropTable(
                name: "studies");

            migrationBuilder.DropTable(
                name: "users");
        }
    }
}
