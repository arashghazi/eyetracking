using EyeTracking.Domain;

namespace EyeTracking.Application;

/// <summary>The signed-in user with everything access checks need.</summary>
public sealed record Principal(int UserId, Role Role, IReadOnlyList<StudyMembership> Memberships, Participant? Participant)
{
    public StudyMembership? Membership(int studyId) => Memberships.FirstOrDefault(m => m.StudyId == studyId);
}

/// <summary>Authorization policy. Every use case that touches study data goes through here.</summary>
public static class Authz
{
    public static void RequireRole(Principal principal, params Role[] roles)
    {
        if (!roles.Contains(principal.Role))
            throw new Forbidden("this action is not available for your role");
    }

    public static Participant RequireParticipant(Principal principal)
    {
        if (principal.Role != Role.Participant || principal.Participant is null)
            throw new Forbidden("participant account required");
        return principal.Participant;
    }

    /// <summary>Study data needs a membership with an allowed study role.
    /// Admins manage users, studies and members (see RequireRole) but do not read study data
    /// unless they are made members explicitly; that keeps every data access grant visible.</summary>
    public static void RequireStudyAccess(Principal principal, int studyId, params StudyRole[] studyRoles)
    {
        var m = principal.Membership(studyId);
        if (m is null || (studyRoles.Length > 0 && !studyRoles.Contains(m.StudyRole)))
            throw new Forbidden("no access to this study");
    }

    /// <summary>The identity &lt;-&gt; research code link needs its own grant, even for admins.</summary>
    public static void RequireIdentityLink(Principal principal, int studyId)
    {
        var m = principal.Membership(studyId);
        if (m is null || !m.CanLinkIdentity)
            throw new Forbidden("identity link permission required");
    }
}
