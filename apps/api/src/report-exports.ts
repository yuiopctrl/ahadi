type Row = Record<string, unknown>

export type ReportExportFormat = 'CSV' | 'XLSX' | 'PDF' | 'PRINT'
export type ReportExportType = 'summary' | 'pledges' | 'payments' | 'outstanding' | 'payment-methods' | 'collectors' | 'member-statement'

interface Column {
  key: string
  label: string
  type?: 'text' | 'money' | 'number' | 'date' | 'datetime' | 'percent'
}

export interface ExportDocumentInput {
  eventName: string
  filtersApplied: Row
  format: ReportExportFormat
  generatedAt: Date
  generatedBy: string
  report: Row
  reportType: ReportExportType
  tenantName: string
}

export interface ExportDocument {
  body: Buffer | string
  contentType: string
  extension: string
}

const moneyFormat = '#,##0'
const dateFormat = 'yyyy-mm-dd'

export function supportedExportFormats(reportType: ReportExportType): ReportExportFormat[] {
  if (reportType === 'summary' || reportType === 'member-statement') return ['PDF', 'PRINT']
  if (reportType === 'payment-methods' || reportType === 'collectors') return ['XLSX', 'PDF', 'PRINT']
  return ['CSV', 'XLSX', 'PDF', 'PRINT']
}

export function reportExportTitle(reportType: ReportExportType) {
  const titles: Record<ReportExportType, string> = {
    summary: 'Collection Summary',
    pledges: 'Pledge Report',
    payments: 'Payment Report',
    outstanding: 'Outstanding Report',
    'payment-methods': 'Payment Method Summary',
    collectors: 'Collector Report',
    'member-statement': 'Member Statement',
  }
  return titles[reportType]
}

export function exportRows(report: Row): Row[] {
  return Array.isArray(report['data']) ? report['data'].filter((row): row is Row => typeof row === 'object' && row !== null && !Array.isArray(row)) : []
}

export function safeFileSlug(input: string) {
  return input
    .normalize('NFKD')
    .replace(/[^\w\s-]/g, '')
    .trim()
    .replace(/[\s_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase()
    .slice(0, 80) || 'report'
}

export function exportColumns(reportType: ReportExportType): Column[] {
  if (reportType === 'pledges') {
    return [
      { key: 'serial', label: 'S/N', type: 'number' },
      { key: 'memberCode', label: 'Member Code' },
      { key: 'member', label: 'Member Name' },
      { key: 'phone', label: 'Phone' },
      { key: 'category', label: 'Category' },
      { key: 'pledged', label: 'Pledged Amount (TZS)', type: 'money' },
      { key: 'paid', label: 'Paid Amount (TZS)', type: 'money' },
      { key: 'outstanding', label: 'Outstanding Amount (TZS)', type: 'money' },
      { key: 'effectiveDueDate', label: 'Effective Due Date', type: 'date' },
      { key: 'status', label: 'Status' },
      { key: 'lastPayment', label: 'Last Payment Date', type: 'datetime' },
    ]
  }
  if (reportType === 'payments') {
    return [
      { key: 'serial', label: 'S/N', type: 'number' },
      { key: 'date', label: 'Payment Date', type: 'datetime' },
      { key: 'paymentNumber', label: 'Payment Number' },
      { key: 'receiptNumber', label: 'Receipt Number' },
      { key: 'member', label: 'Member' },
      { key: 'amount', label: 'Amount (TZS)', type: 'money' },
      { key: 'allocatedAmount', label: 'Allocated Amount (TZS)', type: 'money' },
      { key: 'unallocatedAmount', label: 'Unallocated Amount (TZS)', type: 'money' },
      { key: 'paymentMethod', label: 'Payment Method' },
      { key: 'transactionReference', label: 'Transaction Reference' },
      { key: 'receivedBy', label: 'Collector' },
      { key: 'status', label: 'Status' },
    ]
  }
  if (reportType === 'outstanding') {
    return [
      { key: 'serial', label: 'S/N', type: 'number' },
      { key: 'memberCode', label: 'Member Code' },
      { key: 'member', label: 'Member' },
      { key: 'phone', label: 'Phone' },
      { key: 'category', label: 'Category' },
      { key: 'pledged', label: 'Pledged (TZS)', type: 'money' },
      { key: 'paid', label: 'Paid (TZS)', type: 'money' },
      { key: 'outstanding', label: 'Outstanding (TZS)', type: 'money' },
      { key: 'effectiveDueDate', label: 'Effective Due Date', type: 'date' },
      { key: 'daysOverdue', label: 'Days Overdue', type: 'number' },
      { key: 'status', label: 'Status' },
      { key: 'lastPayment', label: 'Last Payment', type: 'datetime' },
      { key: 'lastReminder', label: 'Last Reminder', type: 'datetime' },
    ]
  }
  if (reportType === 'payment-methods') {
    return [
      { key: 'paymentMethod', label: 'Payment Method' },
      { key: 'paymentCount', label: 'Payment Count', type: 'number' },
      { key: 'grossAmount', label: 'Gross Amount (TZS)', type: 'money' },
      { key: 'reversedAmount', label: 'Reversed Amount (TZS)', type: 'money' },
      { key: 'netConfirmedAmount', label: 'Net Amount (TZS)', type: 'money' },
      { key: 'percentage', label: 'Percentage of Net Collections', type: 'percent' },
    ]
  }
  if (reportType === 'collectors') {
    return [
      { key: 'collectorName', label: 'Collector' },
      { key: 'paymentCount', label: 'Payment Count', type: 'number' },
      { key: 'grossRecorded', label: 'Gross Recorded (TZS)', type: 'money' },
      { key: 'reversed', label: 'Reversed (TZS)', type: 'money' },
      { key: 'netCollected', label: 'Net Collected (TZS)', type: 'money' },
      { key: 'cash', label: 'Cash (TZS)', type: 'money' },
      { key: 'mobileMoney', label: 'Mobile Money (TZS)', type: 'money' },
      { key: 'bank', label: 'Bank (TZS)', type: 'money' },
      { key: 'lastPaymentTime', label: 'Last Payment', type: 'datetime' },
    ]
  }
  if (reportType === 'member-statement') {
    return [
      { key: 'date', label: 'Date', type: 'datetime' },
      { key: 'receipt', label: 'Receipt' },
      { key: 'method', label: 'Payment Method' },
      { key: 'amount', label: 'Amount (TZS)', type: 'money' },
      { key: 'status', label: 'Status' },
    ]
  }
  return [
    { key: 'metric', label: 'Metric' },
    { key: 'value', label: 'Value' },
  ]
}

export function createExportDocument(input: ExportDocumentInput): ExportDocument {
  if (input.format === 'CSV') {
    return { body: createCsv(input.reportType, exportRows(input.report)), contentType: 'text/csv; charset=utf-8', extension: 'csv' }
  }
  if (input.format === 'XLSX') {
    return { body: createXlsx(input), contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', extension: 'xlsx' }
  }
  if (input.format === 'PDF') {
    return { body: createPdf(input), contentType: 'application/pdf', extension: 'pdf' }
  }
  return { body: createPrintHtml(input), contentType: 'text/html; charset=utf-8', extension: 'html' }
}

function createCsv(reportType: ReportExportType, rows: Row[]) {
  const columns = exportColumns(reportType)
  const csvRows = [columns.map((column) => column.label), ...rows.map((row, index) => columns.map((column) => csvValue(valueForColumn(row, column, index))))]
  return `\uFEFF${csvRows.map((row) => row.join(',')).join('\r\n')}\r\n`
}

function csvValue(value: unknown) {
  if (value === null || value === undefined) return ''
  const text = String(value)
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}

function valueForColumn(row: Row, column: Column, index: number) {
  if (column.key === 'serial') return index + 1
  const value = row[column.key]
  if (column.type === 'date') return formatDate(value)
  if (column.type === 'datetime') return formatDateTime(value)
  if (column.type === 'money' || column.type === 'number' || column.type === 'percent') return numericValue(value)
  return value ?? ''
}

function numericValue(value: unknown) {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : 0
  }
  return 0
}

function formatDate(value: unknown) {
  if (typeof value !== 'string' || !value) return ''
  return value.slice(0, 10)
}

function formatDateTime(value: unknown) {
  if (typeof value !== 'string' || !value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return value.slice(0, 19).replace('T', ' ')
  return date.toISOString().slice(0, 19).replace('T', ' ')
}

function createXlsx(input: ExportDocumentInput) {
  const rows = exportRows(input.report)
  const columns = exportColumns(input.reportType)
  const workbookSheets = [
    worksheetXml(reportExportTitle(input.reportType).slice(0, 31), columns, rows),
    summaryWorksheetXml(input),
  ]
  const files: Array<[string, string | Buffer]> = [
    ['[Content_Types].xml', contentTypesXml(workbookSheets.length)],
    ['_rels/.rels', rootRelsXml()],
    ['xl/workbook.xml', workbookXml(workbookSheets.length)],
    ['xl/_rels/workbook.xml.rels', workbookRelsXml(workbookSheets.length)],
    ['xl/styles.xml', stylesXml()],
    ...workbookSheets.map((sheet, index) => [`xl/worksheets/sheet${index + 1}.xml`, sheet] as [string, string]),
  ]
  return zipFiles(files)
}

function worksheetXml(name: string, columns: Column[], rows: Row[]) {
  void name
  const widths = columns.map((column) => `<col min="${columns.indexOf(column) + 1}" max="${columns.indexOf(column) + 1}" width="${Math.max(12, Math.min(column.label.length + 6, 32))}" customWidth="1"/>`).join('')
  const header = `<row r="1">${columns.map((column, index) => cellXml(index, 1, column.label, 'text', true)).join('')}</row>`
  const body = rows.map((row, rowIndex) => {
    const rowNumber = rowIndex + 2
    return `<row r="${rowNumber}">${columns.map((column, columnIndex) => cellXml(columnIndex, rowNumber, valueForColumn(row, column, rowIndex), column.type ?? 'text')).join('')}</row>`
  }).join('')
  const range = `A1:${columnName(columns.length - 1)}${Math.max(rows.length + 1, 1)}`
  return xmlHeader(`<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>${widths}</cols><sheetData>${header}${body}</sheetData><autoFilter ref="${range}"/></worksheet>`)
}

function summaryWorksheetXml(input: ExportDocumentInput) {
  const rows: Array<[string, unknown]> = [
    ['Tenant', input.tenantName],
    ['Event', input.eventName],
    ['Report', reportExportTitle(input.reportType)],
    ['Generated At', input.generatedAt.toISOString()],
    ['Generated By', input.generatedBy],
    ['Currency', 'TZS'],
    ['Filtered Rows', exportRows(input.report).length],
    ...Object.entries(recordValue(input.report['summary'])).map(([key, value]) => [titleCase(key), value] as [string, unknown]),
  ]
  const body = rows.map((row, index) => `<row r="${index + 1}">${cellXml(0, index + 1, row[0], 'text', index === 0)}${cellXml(1, index + 1, scalarSummaryValue(row[1]), typeof scalarSummaryValue(row[1]) === 'number' ? 'number' : 'text')}</row>`).join('')
  return xmlHeader(`<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols><col min="1" max="1" width="28" customWidth="1"/><col min="2" max="2" width="36" customWidth="1"/></cols><sheetData>${body}</sheetData></worksheet>`)
}

function scalarSummaryValue(value: unknown): unknown {
  if (value === null || value === undefined) return ''
  if (typeof value === 'object') return ''
  return value
}

function cellXml(columnIndex: number, rowNumber: number, value: unknown, type: Column['type'] = 'text', bold = false) {
  const ref = `${columnName(columnIndex)}${rowNumber}`
  const style = bold ? 1 : type === 'money' ? 2 : type === 'date' || type === 'datetime' ? 3 : 0
  if (type === 'money' || type === 'number' || type === 'percent') {
    return `<c r="${ref}" s="${style}"><v>${numericValue(value)}</v></c>`
  }
  if ((type === 'date' || type === 'datetime') && typeof value === 'string' && value) {
    const serial = excelDateSerial(value)
    if (serial) return `<c r="${ref}" s="${style}"><v>${serial}</v></c>`
  }
  return `<c r="${ref}" s="${style}" t="inlineStr"><is><t>${xmlEscape(String(value ?? ''))}</t></is></c>`
}

function excelDateSerial(value: string) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return null
  return Math.round(((date.getTime() / 86_400_000) + 25569) * 1_000_000) / 1_000_000
}

function columnName(index: number) {
  let value = ''
  let current = index + 1
  while (current > 0) {
    const remainder = (current - 1) % 26
    value = String.fromCharCode(65 + remainder) + value
    current = Math.floor((current - 1) / 26)
  }
  return value
}

function xmlHeader(body: string) {
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>${body}`
}

function contentTypesXml(sheetCount: number) {
  return xmlHeader(`<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${Array.from({ length: sheetCount }, (_, index) => `<Override PartName="/xl/worksheets/sheet${index + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('')}</Types>`)
}

function rootRelsXml() {
  return xmlHeader('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
}

function workbookXml(sheetCount: number) {
  const names = ['Report', 'Summary']
  return xmlHeader(`<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${Array.from({ length: sheetCount }, (_, index) => `<sheet name="${names[index] ?? `Sheet ${index + 1}`}" sheetId="${index + 1}" r:id="rId${index + 1}"/>`).join('')}</sheets></workbook>`)
}

function workbookRelsXml(sheetCount: number) {
  return xmlHeader(`<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${Array.from({ length: sheetCount }, (_, index) => `<Relationship Id="rId${index + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${index + 1}.xml"/>`).join('')}<Relationship Id="rId${sheetCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`)
}

function stylesXml() {
  return xmlHeader(`<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="164" formatCode="${moneyFormat}"/><numFmt numFmtId="165" formatCode="${dateFormat}"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="1"><fill><patternFill patternType="none"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>`)
}

function createPrintHtml(input: ExportDocumentInput) {
  const rows = exportRows(input.report)
  const columns = exportColumns(input.reportType)
  const summary = recordValue(input.report['summary'])
  return `<!doctype html><html><head><meta charset="utf-8"><title>${htmlEscape(reportExportTitle(input.reportType))}</title><style>
body{font-family:Arial,sans-serif;color:#111;margin:24px}.report-header{border-bottom:2px solid #111;padding-bottom:12px;margin-bottom:16px}.meta{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:6px 18px;font-size:12px}.summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;margin:18px 0}.summary div{border:1px solid #ddd;padding:8px}.summary span{display:block;font-size:11px;color:#555}.summary strong{font-size:14px}table{width:100%;border-collapse:collapse;font-size:11px}th,td{border:1px solid #ddd;padding:6px;vertical-align:top}th{background:#f2f2f2;text-align:left}td.money,td.number{text-align:right}.footer{margin-top:20px;font-size:11px;color:#555}@media print{body{margin:12mm}.no-print{display:none}thead{display:table-header-group}tr{break-inside:avoid}.report-header{break-after:avoid}}
</style></head><body><button class="no-print" onclick="window.print()">Print</button><section class="report-header"><h1>${htmlEscape(reportExportTitle(input.reportType))}</h1><div class="meta"><span>Tenant: ${htmlEscape(input.tenantName)}</span><span>Event: ${htmlEscape(input.eventName)}</span><span>Generated: ${htmlEscape(input.generatedAt.toISOString())}</span><span>Generated by: ${htmlEscape(input.generatedBy)}</span><span>Currency: TZS</span><span>Rows: ${rows.length}</span></div></section><section class="summary">${Object.entries(summary).slice(0, 12).map(([key, value]) => `<div><span>${htmlEscape(titleCase(key))}</span><strong>${htmlEscape(summaryDisplay(value))}</strong></div>`).join('')}</section><table><thead><tr>${columns.map((column) => `<th>${htmlEscape(column.label)}</th>`).join('')}</tr></thead><tbody>${rows.map((row, index) => `<tr>${columns.map((column) => `<td class="${column.type ?? 'text'}">${htmlEscape(String(valueForColumn(row, column, index) ?? ''))}</td>`).join('')}</tr>`).join('')}</tbody></table><p class="footer">This report was generated by Ahadi.</p></body></html>`
}

function createPdf(input: ExportDocumentInput) {
  const rows = exportRows(input.report)
  const columns = exportColumns(input.reportType).slice(0, input.reportType === 'payments' ? 8 : 7)
  const lines = [
    reportExportTitle(input.reportType),
    `Tenant: ${input.tenantName}`,
    `Event: ${input.eventName}`,
    `Generated: ${input.generatedAt.toISOString()}`,
    `Generated by: ${input.generatedBy}`,
    `Currency: TZS`,
    `Rows: ${rows.length}`,
    '',
    ...Object.entries(recordValue(input.report['summary'])).slice(0, 10).map(([key, value]) => `${titleCase(key)}: ${summaryDisplay(value)}`),
    '',
    columns.map((column) => column.label).join(' | '),
    ...rows.map((row, index) => columns.map((column) => String(valueForColumn(row, column, index) ?? '')).join(' | ')),
    '',
    input.reportType === 'member-statement' ? 'This statement was generated by Ahadi.' : 'This report was generated by Ahadi.',
  ]
  return simplePdf(lines, input.reportType === 'summary' || input.reportType === 'member-statement' ? 'portrait' : 'landscape')
}

function simplePdf(lines: string[], orientation: 'portrait' | 'landscape') {
  const width = orientation === 'landscape' ? 842 : 595
  const height = orientation === 'landscape' ? 595 : 842
  const lineHeight = 13
  const linesPerPage = Math.floor((height - 90) / lineHeight)
  const pages: string[] = []
  for (let index = 0; index < lines.length; index += linesPerPage) {
    const pageLines = lines.slice(index, index + linesPerPage)
    const content = ['BT', '/F1 9 Tf', '45 0 0 45 0 0 Tm']
    pageLines.forEach((line, lineIndex) => {
      const y = height - 45 - (lineIndex * lineHeight)
      const fontSize = lineIndex === 0 && index === 0 ? 15 : 9
      content.push(`/F1 ${fontSize} Tf`, `45 ${y} Td`, `(${pdfEscape(line).slice(0, 180)}) Tj`)
    })
    content.push('ET')
    pages.push(content.join('\n'))
  }
  const objects: string[] = ['<< /Type /Catalog /Pages 2 0 R >>']
  const pageKids: string[] = []
  objects.push('')
  pages.forEach((content, index) => {
    const pageObjectNumber = objects.length + 1
    const contentObjectNumber = pageObjectNumber + 1
    pageKids.push(`${pageObjectNumber} 0 R`)
    objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${width} ${height}] /Resources << /Font << /F1 3 0 R >> >> /Contents ${contentObjectNumber} 0 R >>`)
    objects.push(`<< /Length ${Buffer.byteLength(content)} >>\nstream\n${content}\nendstream`)
  })
  objects[1] = `<< /Type /Pages /Kids [${pageKids.join(' ')}] /Count ${pages.length} >>`
  objects.splice(2, 0, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
  return buildPdf(objects)
}

function buildPdf(objects: string[]) {
  const parts = ['%PDF-1.4\n']
  const offsets: number[] = [0]
  for (let index = 0; index < objects.length; index += 1) {
    offsets.push(Buffer.byteLength(parts.join('')))
    parts.push(`${index + 1} 0 obj\n${objects[index]}\nendobj\n`)
  }
  const xrefOffset = Buffer.byteLength(parts.join(''))
  parts.push(`xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`)
  offsets.slice(1).forEach((offset) => parts.push(`${String(offset).padStart(10, '0')} 00000 n \n`))
  parts.push(`trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`)
  return Buffer.from(parts.join(''), 'utf8')
}

function zipFiles(files: Array<[string, string | Buffer]>) {
  const localParts: Buffer[] = []
  const centralParts: Buffer[] = []
  let offset = 0
  files.forEach(([name, value]) => {
    const data = Buffer.isBuffer(value) ? value : Buffer.from(value, 'utf8')
    const nameBuffer = Buffer.from(name)
    const crc = crc32(data)
    const local = Buffer.alloc(30)
    local.writeUInt32LE(0x04034b50, 0)
    local.writeUInt16LE(20, 4)
    local.writeUInt16LE(0, 6)
    local.writeUInt16LE(0, 8)
    local.writeUInt16LE(0, 10)
    local.writeUInt16LE(0, 12)
    local.writeUInt32LE(crc, 14)
    local.writeUInt32LE(data.length, 18)
    local.writeUInt32LE(data.length, 22)
    local.writeUInt16LE(nameBuffer.length, 26)
    local.writeUInt16LE(0, 28)
    localParts.push(local, nameBuffer, data)
    const central = Buffer.alloc(46)
    central.writeUInt32LE(0x02014b50, 0)
    central.writeUInt16LE(20, 4)
    central.writeUInt16LE(20, 6)
    central.writeUInt16LE(0, 8)
    central.writeUInt16LE(0, 10)
    central.writeUInt16LE(0, 12)
    central.writeUInt16LE(0, 14)
    central.writeUInt32LE(crc, 16)
    central.writeUInt32LE(data.length, 20)
    central.writeUInt32LE(data.length, 24)
    central.writeUInt16LE(nameBuffer.length, 28)
    central.writeUInt16LE(0, 30)
    central.writeUInt16LE(0, 32)
    central.writeUInt16LE(0, 34)
    central.writeUInt16LE(0, 36)
    central.writeUInt32LE(0, 38)
    central.writeUInt32LE(offset, 42)
    centralParts.push(central, nameBuffer)
    offset += local.length + nameBuffer.length + data.length
  })
  const centralSize = centralParts.reduce((sum, part) => sum + part.length, 0)
  const end = Buffer.alloc(22)
  end.writeUInt32LE(0x06054b50, 0)
  end.writeUInt16LE(0, 4)
  end.writeUInt16LE(0, 6)
  end.writeUInt16LE(files.length, 8)
  end.writeUInt16LE(files.length, 10)
  end.writeUInt32LE(centralSize, 12)
  end.writeUInt32LE(offset, 16)
  end.writeUInt16LE(0, 20)
  return Buffer.concat([...localParts, ...centralParts, end])
}

const crcTable = Array.from({ length: 256 }, (_, index) => {
  let value = index
  for (let bit = 0; bit < 8; bit += 1) value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1
  return value >>> 0
})

function crc32(buffer: Buffer) {
  let crc = 0xffffffff
  for (const byte of buffer) crc = crcTable[(crc ^ byte) & 0xff]! ^ (crc >>> 8)
  return (crc ^ 0xffffffff) >>> 0
}

function recordValue(value: unknown): Row {
  return typeof value === 'object' && value !== null && !Array.isArray(value) ? value as Row : {}
}

function titleCase(input: string) {
  return input.replace(/([A-Z])/g, ' $1').replace(/[_-]/g, ' ').replace(/\b\w/g, (match) => match.toUpperCase()).trim()
}

function summaryDisplay(value: unknown) {
  if (value === null || value === undefined) return ''
  if (typeof value === 'object') return ''
  return String(value)
}

function xmlEscape(value: string) {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

function htmlEscape(value: string) {
  return xmlEscape(value).replace(/'/g, '&#39;')
}

function pdfEscape(value: string) {
  return value.replace(/[^\x09\x0a\x0d\x20-\x7e]/g, '?').replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)')
}
