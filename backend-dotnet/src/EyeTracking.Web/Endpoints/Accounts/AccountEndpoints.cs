using System.Text.Json.Nodes;
using EyeTracking.Application;
using EyeTracking.Domain;
using EyeTracking.Web.Http;
using static EyeTracking.Web.Endpoints.Accounts.AccountMappers;

namespace EyeTracking.Web.Endpoints.Accounts;

/// <summary>Sign-in and the caller's account (backend/eyetracking/web/routers/auth.py).</summary>
public sealed class AuthEndpoints : IEndpointModule
{
    public void Map(IEndpointRouteBuilder app)
    {
        app.MapPost("/auth/login", async (HttpContext ctx, IUnitOfWork uow, IPasswordHasher hasher, ITokenIssuer tokens) =>
        {
            var body = await ctx.Body<LoginIn>();
            var (token, user) = UseCases.Login(uow, hasher, tokens, body.Email, body.Password);
            var participant = user.Role == Role.Participant ? uow.Participants.ByUser(user.Id) : null;
            return Reply.Ok(new TokenOut(token, user.Role.Value(), participant?.Code));
        });

        app.MapPost("/invitations/{token}/accept", async (HttpContext ctx, string token, IUnitOfWork uow, IPasswordHasher hasher, ITokenIssuer tokens, IClock clock) =>
        {
            var body = await ctx.Body<AcceptInvitationIn>();
            var (access, participant) = UseCases.AcceptInvitation(uow, hasher, tokens, clock, token, body.Email, body.Password);
            return Reply.Ok(new TokenOut(access, "participant", participant.Code));
        });

        app.MapGet("/me", (HttpContext ctx, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var user = uow.Users.Get(principal.UserId)!;
            var p = principal.Participant;
            return Reply.Ok(new MeOut(user.Id, user.Email, user.Role.Value(), p is null ? null : new ParticipantRef(p.Code, p.StudyId)));
        });
    }
}

/// <summary>Research Admin endpoints (backend/eyetracking/web/routers/studies.py).
/// Access is checked in the application layer for every call.</summary>
public sealed class StudyEndpoints : IEndpointModule
{
    public void Map(IEndpointRouteBuilder app)
    {
        app.MapPost("/users", async (HttpContext ctx, IUnitOfWork uow, IPasswordHasher hasher) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<UserIn>();
            var user = UseCases.CreateUser(uow, hasher, principal, body.Email, body.Password, Wire.Parse<Role>(body.Role));
            return Reply.Created(new UserOut(user.Id, user.Email, user.Role.Value()));
        });

        app.MapGet("/studies", (HttpContext ctx, IUnitOfWork uow) =>
            Reply.Ok(UseCases.ListStudies(uow, ctx.Principal()).Select(s => new StudyOut(s.Id, s.Name))));

        app.MapPost("/studies", async (HttpContext ctx, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<StudyIn>();
            var study = UseCases.CreateStudy(uow, principal, body.Name);
            return Reply.Created(new StudyOut(study.Id, study.Name));
        });

        app.MapPost("/studies/{studyId:int}/members", async (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<MemberIn>();
            var m = UseCases.AddMember(uow, principal, studyId, body.UserId, Wire.Parse<StudyRole>(body.StudyRole), body.CanLinkIdentity);
            return Reply.Created(new MemberOut(m.UserId, m.StudyRole.Value(), m.CanLinkIdentity, m.StudyId));
        });

        app.MapPost("/studies/{studyId:int}/invitations", async (HttpContext ctx, int studyId, IUnitOfWork uow, IClock clock) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<InvitationIn>();
            var inv = UseCases.CreateInvitation(uow, clock, principal, studyId, body.InviteeEmail, body.ExpiresDays);
            return Reply.Created(new InvitationOut(inv.Token, inv.Code, inv.ExpiresAt));
        });

        app.MapGet("/studies/{studyId:int}/participants", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
            Reply.Ok(UseCases.ListParticipants(uow, ctx.Principal(), studyId).Select(Coded)));

        app.MapGet("/studies/{studyId:int}/participants/{code}", (HttpContext ctx, int studyId, string code, IUnitOfWork uow) =>
            Reply.Ok(Coded(UseCases.GetParticipant(uow, ctx.Principal(), studyId, code))));

        app.MapGet("/studies/{studyId:int}/participants/{code}/identity", (HttpContext ctx, int studyId, string code, IUnitOfWork uow) =>
            Reply.Ok(new IdentityOut(UseCases.GetParticipantIdentity(uow, ctx.Principal(), studyId, code))));

        app.MapGet("/studies/{studyId:int}/information-sheet", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var sheet = UseCases.GetStudySheet(uow, ctx.Principal(), studyId)
                ?? throw new HttpError(404, "no information sheet has been published yet");
            return Reply.Ok(Sheet(sheet));
        });

        app.MapPut("/studies/{studyId:int}/information-sheet", async (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<SheetIn>();
            return Reply.Ok(Sheet(UseCases.PublishInformationSheet(uow, principal, studyId, b.Aims, b.DiscomfortSources, b.Benefits, b.DataHandling, b.StopRules)));
        });

        app.MapGet("/studies/{studyId:int}/demographics-form", (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var form = UseCases.GetStudyForm(uow, ctx.Principal(), studyId)
                ?? throw new HttpError(404, "this study has no demographics form");
            return Reply.Ok(Form(form));
        });

        app.MapPut("/studies/{studyId:int}/demographics-form", async (HttpContext ctx, int studyId, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var body = await ctx.Body<DemographicsFormIn>();
            var fields = new JsonArray(body.Fields.Select(f => (JsonNode?)StoredField(f)).ToArray());
            return Reply.Ok(Form(UseCases.PublishDemographicsForm(uow, principal, studyId, fields)));
        });
    }
}

/// <summary>Endpoints a participant uses for their own data (backend/eyetracking/web/routers/participant.py).
/// Everything is scoped to the caller.</summary>
public sealed class ParticipantEndpoints : IEndpointModule
{
    public void Map(IEndpointRouteBuilder app)
    {
        var me = app.MapGroup("/me");

        me.MapGet("/participant", (HttpContext ctx, IUnitOfWork uow) =>
        {
            var view = UseCases.MyParticipantView(uow, ctx.Principal());
            return Reply.Ok(new ParticipantMeOut(view.Participant.Code, view.Participant.StudyId, Readiness(view), Consent(view.Consent)));
        });

        me.MapGet("/information-sheet", (HttpContext ctx, IUnitOfWork uow) =>
        {
            var sheet = UseCases.MyInformationSheet(uow, ctx.Principal())
                ?? throw new HttpError(404, "no information sheet has been published yet");
            return Reply.Ok(Sheet(sheet));
        });

        me.MapPost("/consent", async (HttpContext ctx, IUnitOfWork uow, IClock clock) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<ConsentIn>();
            return Reply.Ok(Consent(UseCases.GiveConsent(uow, clock, principal, b.SheetVersion, b.Participate, b.AudioRecording, b.VideoRecording)));
        });

        me.MapPost("/consent/withdraw", (HttpContext ctx, IUnitOfWork uow, IClock clock) =>
            Reply.Ok(Consent(UseCases.WithdrawConsent(uow, clock, ctx.Principal()))));

        me.MapGet("/profile", (HttpContext ctx, IUnitOfWork uow) => Reply.Ok(Profile(UseCases.GetProfile(uow, ctx.Principal()))));

        me.MapPut("/profile", async (HttpContext ctx, IUnitOfWork uow) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<ProfileIn>();
            var changes = new ProfileChanges(b.DisplayName, b.ResponseMode, b.VoicePreference, b.FacePreference, b.Speed, b.AccessibilityNeeds, b.Interests);
            return Reply.Ok(Profile(UseCases.UpdateProfile(uow, principal, changes)));
        });

        me.MapGet("/demographics-form", (HttpContext ctx, IUnitOfWork uow) =>
        {
            var form = UseCases.MyDemographicsForm(uow, ctx.Principal())
                ?? throw new HttpError(404, "this study has no demographics form");
            return Reply.Ok(Form(form));
        });

        me.MapGet("/demographics", (HttpContext ctx, IUnitOfWork uow) =>
        {
            var view = UseCases.MyParticipantView(uow, ctx.Principal());
            if (view.Demographics is null)
                throw new HttpError(404, "no demographics answers yet");
            return Reply.Ok(Answers(view.Demographics));
        });

        me.MapPut("/demographics", async (HttpContext ctx, IUnitOfWork uow, IClock clock) =>
        {
            var principal = ctx.Principal();
            var b = await ctx.Body<DemographicsAnswersIn>();
            return Reply.Ok(Answers(UseCases.SubmitDemographics(uow, clock, principal, b.Answers)));
        });
    }
}
