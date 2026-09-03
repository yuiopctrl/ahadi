/// Mirrors the permission codes checked server-side in
/// apps/api/src/middleware.ts and supabase has_platform_permission().
/// These constants are UX-only shortcuts for showing/hiding navigation and
/// controls -- the backend is the sole source of authorization truth.
class PlatformPermission {
  static const dashboardView = 'platform.dashboard.view';
  static const tenantsView = 'platform.tenants.view';
  static const tenantsManage = 'platform.tenants.manage';
  static const plansView = 'platform.plans.view';
  static const plansManage = 'platform.plans.manage';
  static const subscriptionsManage = 'platform.subscriptions.manage';
  static const smsView = 'platform.sms.view';
  static const smsManage = 'platform.sms.manage';
  static const betaView = 'platform.beta.view';
  static const betaManage = 'platform.beta.manage';
  static const supportView = 'platform.support.view';
  static const supportManage = 'platform.support.manage';
  static const supportSessionStart = 'platform.support_session.start';
  static const usersView = 'platform.users.view';
  static const usersManage = 'platform.users.manage';
  static const auditView = 'platform.audit.view';
  static const systemErrorsView = 'platform.system_errors.view';
}
