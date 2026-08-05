import { Building2, MessageSquareText, Package, ShieldCheck } from 'lucide-react'
import { EmptyState, PageContainer, PageHeader, StatCard, StatusBadge } from '../components/ui'

export function PlatformPage({ title }: { title: string }) {
  return (
    <PageContainer>
      <PageHeader title={title} description="Platform owner controls for tenants, packages, SMS activity and audit oversight." />
      <section className="stats-grid">
        <StatCard label="Tenants" value="24" meta="19 active" icon={Building2} />
        <StatCard label="Packages" value="4" meta="Community to Enterprise" icon={Package} />
        <StatCard label="SMS Sent" value="12,480" meta="This month" icon={MessageSquareText} />
        <StatCard label="Audit Events" value="832" meta="Last 7 days" icon={ShieldCheck} tone="success" />
      </section>
      <article className="platform-panel">
        <div className="panel-header">
          <div>
            <h2>Tenant Health</h2>
            <p>Operational snapshot across subscription and collection activity.</p>
          </div>
          <StatusBadge tone="success">Stable</StatusBadge>
        </div>
        <div className="responsive-table" role="region" aria-label="Tenant health table">
          <table>
            <thead>
              <tr>
                <th>Tenant</th>
                <th>Plan</th>
                <th>Status</th>
                <th>Collections</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Mrema Family Committee</td>
                <td>Community</td>
                <td>Active</td>
                <td>TZS 31.4M</td>
              </tr>
              <tr>
                <td>Kijitonyama Fundraising</td>
                <td>Growth</td>
                <td>Active</td>
                <td>TZS 8.9M</td>
              </tr>
            </tbody>
          </table>
        </div>
      </article>
      <EmptyState title="Security boundary established" message="Platform routes are isolated from tenant navigation and ready for owner-only authorization." />
    </PageContainer>
  )
}
