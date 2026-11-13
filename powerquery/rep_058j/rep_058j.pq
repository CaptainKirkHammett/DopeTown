// =====================================================================
// REP_058J – AP reconciliation (Impala), parameterised for Power Query
// ---------------------------------------------------------------------
// Required queries/parameters in the same .pbix (see parameters.pq):
//   PartitionDate      Date (or "yyyy-MM-dd" text)   e.g. 2026-11-10
//   SourceTablePrefix  Text, may be empty             e.g. one_int_
//   ConnectionString   Text / record for Odbc.Query  (provided elsewhere)
// Optional – edit the defaults below or turn them into parameters too:
//   SourceSchema, StartDate, PayeeSegment
// =====================================================================
let
    // ---- optional inputs (defaults = original SQL defaults) ---------------
    SourceSchemaInput = "master_alfa5_alfaods",
    StartDateInput    = null,            // null/"" -> report date = PartitionDate
    PayeeSegmentInput = "COUNTRY_FI",

    // ---- helpers -----------------------------------------------------------
    ToDate = (value as any, name as text) as date =>
        if value is date then value
        else if value is datetime or value is datetimezone then Date.From(value)
        else if value is text then
            try Date.FromText(Text.Trim(value), [Format = "yyyy-MM-dd", Culture = "en-US"])
            otherwise error Error.Record("Invalid parameter", name & " must be a date or 'yyyy-MM-dd' text", value)
        else error Error.Record("Invalid parameter", name & " must be a date", value),

    DateToSql = (d as date) as text => Date.ToText(d, [Format = "yyyy-MM-dd", Culture = "en-US"]),

    // Only letters, digits and underscore are allowed in identifiers / codes,
    // so nothing can break out of the SQL text (no quotes, spaces, dots, ;).
    SafeChars = {"A".."Z", "a".."z", "0".."9", "_"},
    CheckSafe = (value as nullable text, name as text, allowEmpty as logical) as text =>
        let v = if value = null then "" else Text.Trim(value)
        in  if v = "" and not allowEmpty then
                error Error.Record("Invalid parameter", name & " must not be empty")
            else if Text.Length(Text.Select(v, SafeChars)) <> Text.Length(v) then
                error Error.Record("Invalid parameter", name & " may contain only A-Z, a-z, 0-9 and _", v)
            else v,

    // ---- validated values that go into the SQL -----------------------------
    pPartitionDate     = DateToSql(ToDate(PartitionDate, "PartitionDate")),
    pSourceTablePrefix = CheckSafe(SourceTablePrefix, "SourceTablePrefix", true),
    pSourceSchema      = CheckSafe(SourceSchemaInput, "SourceSchema", false),
    pStartDate         = if StartDateInput = null or StartDateInput = ""
                         then ""                                   // SQL falls back to PartitionDate
                         else DateToSql(ToDate(StartDateInput, "StartDate")),
    pPayeeSegment      = CheckSafe(PayeeSegmentInput, "PayeeSegment", false),

    // ---- SQL template ({{...}} tokens are replaced below) ------------------
    SqlTemplate = "/* Direct ODS DATA058J; parity filters and fex_line references follow the source SQL. */
WITH digits AS (
  SELECT 1 AS k, CAST(0 AS INT) AS n
  UNION ALL SELECT 1, 1
  UNION ALL SELECT 1, 2
  UNION ALL SELECT 1, 3
  UNION ALL SELECT 1, 4
  UNION ALL SELECT 1, 5
  UNION ALL SELECT 1, 6
  UNION ALL SELECT 1, 7
  UNION ALL SELECT 1, 8
  UNION ALL SELECT 1, 9
),
day_offsets AS (
  SELECT d0.n + d1.n * 10 + d2.n * 100 + d3.n * 1000 + d4.n * 10000 AS day_offset
  FROM digits d0
  JOIN digits d1 ON d1.k = d0.k
  JOIN digits d2 ON d2.k = d0.k
  JOIN digits d3 ON d3.k = d0.k
  JOIN digits d4 ON d4.k = d0.k
),
calendar_days AS (
  SELECT
    CAST(DATE_ADD(CAST('1990-01-01' AS DATE), o.day_offset) AS DATE) AS calendar_date,
    PMOD(o.day_offset + 0, 7) AS weekday_index
  FROM day_offsets o
  WHERE o.day_offset < 40177
),
dim_date_source AS (
SELECT
  CAST(cal.calendar_date AS DATE) AS calendar_date,
  CAST(CAST(YEAR(cal.calendar_date) AS INT) AS INT) AS year_num,
  CAST(CAST(FLOOR((MONTH(cal.calendar_date) - 1) / 3) + 1 AS INT) AS INT) AS quarter_num,
  CAST(CAST(MONTH(cal.calendar_date) AS INT) AS INT) AS month_num,
  CAST(CAST(CASE MONTH(cal.calendar_date) WHEN 1 THEN 'January' WHEN 2 THEN 'February' WHEN 3 THEN 'March' WHEN 4 THEN 'April' WHEN 5 THEN 'May' WHEN 6 THEN 'June' WHEN 7 THEN 'July' WHEN 8 THEN 'August' WHEN 9 THEN 'September' WHEN 10 THEN 'October' WHEN 11 THEN 'November' WHEN 12 THEN 'December' END AS STRING) AS STRING) AS month_name,
  CAST(CAST(cal.weekday_index < 5 AS BOOLEAN) AS BOOLEAN) AS is_business_day,
  CAST(CAST(YEAR(cal.calendar_date) * 10000 + MONTH(cal.calendar_date) * 100 + DAY(cal.calendar_date) AS BIGINT) AS BIGINT) AS date_key,
  CAST(CAST(DAY(cal.calendar_date) AS INT) AS INT) AS day_of_month,
  CAST(CAST(WEEKOFYEAR(cal.calendar_date) AS INT) AS INT) AS week_of_year
FROM calendar_days cal
),
dim_date AS (
SELECT
  CAST(source.calendar_date AS DATE) AS calendar_date,
  CAST(source.year_num AS INT) AS year_num,
  CAST(source.quarter_num AS INT) AS quarter_num,
  CAST(source.month_num AS INT) AS month_num,
  CAST(source.month_name AS STRING) AS month_name,
  CAST(source.is_business_day AS BOOLEAN) AS is_business_day,
  CAST(source.date_key AS BIGINT) AS date_key,
  CAST(source.day_of_month AS INT) AS day_of_month,
  CAST(source.week_of_year AS INT) AS week_of_year,
  CAST('{{PartitionDate}}' AS STRING) AS business_date
FROM dim_date_source source
),
dim_agreement_source AS (
SELECT
  CAST(CAST(src.id AS BIGINT) AS BIGINT) AS agreement_id,
  CAST(CAST(src.alfaAgreementIdentifier AS BIGINT) AS BIGINT) AS alfa_agreement_identifier,
  CAST(src.agreementNumber AS STRING) AS agreement_number,
  CAST(src.agreementType AS STRING) AS agreement_type,
  CAST(src.productCode AS STRING) AS product_code,
  CAST(src.product AS STRING) AS product,
  CAST(src.branchCode AS STRING) AS branch_code,
  CAST(src.country AS STRING) AS country,
  CAST(src.region AS STRING) AS region,
  CAST(src.productGroupCode AS STRING) AS product_group_code,
  CAST(src.productGroupName AS STRING) AS product_group_name,
  CAST(CAST(src.currentDamageClaim AS DECIMAL(13,2)) AS DECIMAL(13,2)) AS current_damage_claim,
  CAST(src.segmentCode AS STRING) AS segment_code,
  CAST(CASE LOWER(TRIM(CAST(src.hasGuarantee AS STRING))) WHEN '1' THEN TRUE WHEN 'true' THEN TRUE WHEN '0' THEN FALSE WHEN 'false' THEN FALSE ELSE NULL END AS BOOLEAN) AS has_guarantee,
  CAST(src.keyAccountManagerCode AS STRING) AS key_account_manager_code,
  CAST(src.keyAccountManagerName AS STRING) AS key_account_manager_name
FROM {{SourceSchema}}.{{SourceTablePrefix}}OdsAgreement src
WHERE CAST(src.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
),
dim_agreement AS (
SELECT
  CAST(source.agreement_id AS BIGINT) AS agreement_id,
  CAST(source.alfa_agreement_identifier AS BIGINT) AS alfa_agreement_identifier,
  CAST(source.agreement_number AS STRING) AS agreement_number,
  CAST(source.agreement_type AS STRING) AS agreement_type,
  CAST(source.product_code AS STRING) AS product_code,
  CAST(source.product AS STRING) AS product,
  CAST(source.branch_code AS STRING) AS branch_code,
  CAST(source.country AS STRING) AS country,
  CAST(source.region AS STRING) AS region,
  CAST(source.product_group_code AS STRING) AS product_group_code,
  CAST(source.product_group_name AS STRING) AS product_group_name,
  CAST(source.current_damage_claim AS DECIMAL(13,2)) AS current_damage_claim,
  CAST(source.segment_code AS STRING) AS segment_code,
  CAST(source.has_guarantee AS BOOLEAN) AS has_guarantee,
  CAST(source.key_account_manager_code AS STRING) AS key_account_manager_code,
  CAST(source.key_account_manager_name AS STRING) AS key_account_manager_name,
  CAST('{{PartitionDate}}' AS STRING) AS business_date
FROM dim_agreement_source source
),
dim_payee_source AS (
SELECT
  CAST(src.id AS BIGINT) AS payee_id,
  CAST(src.payeeThirdPartyNumber AS STRING) AS payee_third_party_number,
  CAST(src.payeeName AS STRING) AS payee_name,
  CAST(src.payeeSegmentCode AS STRING) AS payee_segment_code
FROM {{SourceSchema}}.{{SourceTablePrefix}}OdsPayee src
WHERE CAST(src.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
),
dim_payee AS (
SELECT
  CAST(source.payee_id AS BIGINT) AS payee_id,
  CAST(source.payee_third_party_number AS STRING) AS payee_third_party_number,
  CAST(source.payee_name AS STRING) AS payee_name,
  CAST(source.payee_segment_code AS STRING) AS payee_segment_code,
  CAST('{{PartitionDate}}' AS STRING) AS business_date
FROM dim_payee_source source
),
dim_schedule_source AS (
SELECT
  CAST(src.id AS BIGINT) AS schedule_id,
  CAST(src.scheduleRef AS STRING) AS schedule_ref,
  CAST(src.agreementId AS BIGINT) AS agreement_id
FROM {{SourceSchema}}.{{SourceTablePrefix}}OdsScheduleMain src
WHERE CAST(src.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
),
dim_schedule AS (
SELECT
  CAST(source.schedule_id AS BIGINT) AS schedule_id,
  CAST(source.schedule_ref AS STRING) AS schedule_ref,
  CAST(source.agreement_id AS BIGINT) AS agreement_id,
  CAST('{{PartitionDate}}' AS STRING) AS business_date
FROM dim_schedule_source source
),
stg_fact_ap_reconciliation_supplier_invoice_driver AS (
SELECT
  CAST(line.id AS BIGINT) AS supplier_invoice_line_id,
  CAST(line.supplierInvoiceId AS BIGINT) AS supplier_invoice_id,
  CAST(line.scheduleId AS BIGINT) AS schedule_id,
  CAST(line.supplierInvoiceAmount AS DECIMAL(13,2)) AS supplier_invoice_amount,
  CAST(line.supplierInvoiceVATAmount AS DECIMAL(13,2)) AS supplier_invoice_vat_amount
FROM {{SourceSchema}}.{{SourceTablePrefix}}OdsSupplierInvoiceLine line
WHERE CAST(line.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
  AND CAST(line.id AS BIGINT) NOT IN (1, 2)
),
fact_ap_reconciliation_supplier_invoice AS (
SELECT
  CAST(driver.supplier_invoice_line_id AS BIGINT) AS supplier_invoice_line_id,
  CAST(driver.schedule_id AS BIGINT) AS schedule_id,
  CAST(invoice.payeeId AS BIGINT) AS payee_id,
  CAST(REPLACE(CAST(CAST(invoice.invoiceReceivedDate AS DATE) AS STRING), '-', '') AS BIGINT) AS invoice_received_date_key,
  CAST(driver.supplier_invoice_amount AS DECIMAL(13,2)) AS supplier_invoice_amount,
  CAST(driver.supplier_invoice_vat_amount AS DECIMAL(13,2)) AS supplier_invoice_vat_amount,
  CAST(driver.supplier_invoice_amount + driver.supplier_invoice_vat_amount AS DECIMAL(14,2)) AS supplier_invoice_total_amount,
  CAST(invoice.invoiceReceivedDate AS DATE) AS invoice_received_date,
  CAST(invoice.payeeReference AS STRING) AS payee_reference,
  CAST(currency.supInvCurrencyCode AS STRING) AS supplier_invoice_currency_code
FROM stg_fact_ap_reconciliation_supplier_invoice_driver driver
INNER JOIN {{SourceSchema}}.{{SourceTablePrefix}}OdsSupplierInvoice invoice /* fex_line 64 */
  ON driver.supplier_invoice_id = CAST(invoice.id AS BIGINT)
INNER JOIN {{SourceSchema}}.{{SourceTablePrefix}}OdsSupplierInvoiceCurrency currency /* fex_line 70 */
  ON CAST(invoice.supInvCurrencyId AS BIGINT) = CAST(currency.id AS BIGINT)
INNER JOIN dim_schedule schedule /* fex_line 67, 180 */
  ON driver.schedule_id = schedule.schedule_id
 AND schedule.business_date = '{{PartitionDate}}'
INNER JOIN dim_agreement agreement /* fex_line 183 */
  ON schedule.agreement_id = agreement.agreement_id
 AND agreement.business_date = '{{PartitionDate}}'
INNER JOIN dim_payee payee /* fex_line 73 */
  ON CAST(invoice.payeeId AS BIGINT) = payee.payee_id
 AND payee.business_date = '{{PartitionDate}}'
WHERE CAST(invoice.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
  AND CAST(currency.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
  AND schedule.agreement_id <> 1
),
stg_fact_ap_reconciliation_cash_allocation_base AS (
SELECT
  CAST(allocation.id AS BIGINT) AS cash_allocation_id,
  CAST(allocation.scheduleId AS BIGINT) AS schedule_id,
  CAST(txn.appliedDate AS DATE) AS applied_date,
  CAST(txn.effectiveDate AS DATE) AS effective_date,
  CAST(allocation.totalAmount AS DECIMAL(13,2)) AS cash_allocation_amount
FROM {{SourceSchema}}.{{SourceTablePrefix}}OdsCashAllocation allocation
INNER JOIN {{SourceSchema}}.{{SourceTablePrefix}}OdsCashAllocationTxn txn /* fex_line 23 */
  ON CAST(allocation.cashAllocationTransactionId AS BIGINT) = CAST(txn.id AS BIGINT)
INNER JOIN {{SourceSchema}}.{{SourceTablePrefix}}OdsCashInOut cash /* fex_line 26 */
  ON CAST(txn.cashId AS BIGINT) = CAST(cash.id AS BIGINT)
INNER JOIN {{SourceSchema}}.{{SourceTablePrefix}}OdsCashAllocationPaymentType payment_type /* fex_line 29 */
  ON CAST(cash.paymentTypeId AS BIGINT) = CAST(payment_type.id AS BIGINT)
/* fex_line 32: the operator retained allocation.companyId = OdsCompany.id as authored; */
/* catalog FK metadata instead identifies OdsCashAllocationCompany. */
INNER JOIN {{SourceSchema}}.{{SourceTablePrefix}}OdsCompany company /* fex_line 32 */
  ON CAST(allocation.companyId AS BIGINT) = CAST(company.id AS BIGINT)
WHERE CAST(allocation.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
  AND CAST(txn.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
  AND CAST(cash.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
  AND CAST(payment_type.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
  AND CAST(company.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
  AND company.countryName = 'FINLAND' /* fex_line 44 */
  AND (NOT (cash.processingStatus IN ('Cancelled') AND CAST(txn.effectiveDate AS DATE) >= CAST('2018-01-15' AS DATE)
       AND CAST(txn.effectiveDate AS DATE) <= CAST('2018-11-18' AS DATE))
       OR CAST(txn.effectiveDate AS DATE) < CAST('2018-01-15' AS DATE)) /* fex_line 48 */
  AND (payment_type.cshAllcPaymentTypeName IN ('Manual Payout', 'Payment to account', 'FI Payment to account')
       OR (allocation.locationType = 'Supplier invoice line'
           AND CAST(allocation.totalAmount AS DECIMAL(13,2)) IN (0.01, -0.01))) /* fex_line 51 */
  AND txn.status = 'Applied' /* fex_line 54 */
  AND txn.reasonCode <> '01'
),
fact_ap_reconciliation_cash_allocation AS (
SELECT
  CAST(base.cash_allocation_id AS BIGINT) AS cash_allocation_id,
  CAST(base.schedule_id AS BIGINT) AS schedule_id,
  CAST(REPLACE(CAST(base.applied_date AS STRING), '-', '') AS BIGINT) AS applied_date_key,
  CAST(base.cash_allocation_amount AS DECIMAL(13,2)) AS cash_allocation_amount,
  CAST(base.applied_date AS DATE) AS applied_date,
  CAST(base.effective_date AS DATE) AS effective_date
FROM stg_fact_ap_reconciliation_cash_allocation_base base
INNER JOIN dim_schedule schedule /* fex_line 180 */
  ON base.schedule_id = schedule.schedule_id
 AND schedule.business_date = '{{PartitionDate}}'
INNER JOIN dim_agreement agreement /* fex_line 183 */
  ON schedule.agreement_id = agreement.agreement_id
 AND agreement.business_date = '{{PartitionDate}}'
WHERE schedule.agreement_id <> 1
),
stg_fact_ap_reconciliation_posting_base AS (
SELECT
  CAST(posting.id AS BIGINT) AS posting_line_id,
  CAST(posting.scheduleId AS BIGINT) AS schedule_id,
  CAST(posting.postingDate AS DATE) AS posting_date,
  CAST(posting.amountBase AS DECIMAL(13,2)) AS amount_base,
  CAST(account.accountNumber AS STRING) AS gl_account_number
FROM {{SourceSchema}}.{{SourceTablePrefix}}OdsPostingLine posting
INNER JOIN {{SourceSchema}}.{{SourceTablePrefix}}OdsAccount account /* fex_line 97 */
  ON CAST(posting.glAccountId AS BIGINT) = CAST(account.id AS BIGINT)
INNER JOIN {{SourceSchema}}.{{SourceTablePrefix}}OdsCompany company /* fex_line 107 */
  ON CAST(posting.companyId AS BIGINT) = CAST(company.id AS BIGINT)
WHERE CAST(posting.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
  AND CAST(account.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
  AND CAST(company.business_date AS DATE) = CAST('{{PartitionDate}}' AS DATE)
  AND company.countryCode = 'FI' /* fex_line 118 */
  AND account.accountNumber IN ('2280', '2567', '1890', '2564')
),
fact_ap_reconciliation_posting AS (
SELECT
  CAST(base.posting_line_id AS BIGINT) AS posting_line_id,
  CAST(base.schedule_id AS BIGINT) AS schedule_id,
  CAST(REPLACE(CAST(base.posting_date AS STRING), '-', '') AS BIGINT) AS posting_date_key,
  CAST(base.amount_base AS DECIMAL(13,2)) AS amount_base,
  CAST(base.posting_date AS DATE) AS posting_date,
  CAST(base.gl_account_number AS STRING) AS gl_account_number
FROM stg_fact_ap_reconciliation_posting_base base
INNER JOIN dim_schedule schedule /* fex_line 101, 180 */
  ON base.schedule_id = schedule.schedule_id
 AND schedule.business_date = '{{PartitionDate}}'
INNER JOIN dim_agreement agreement /* fex_line 104, 183 */
  ON schedule.agreement_id = agreement.agreement_id
 AND agreement.business_date = '{{PartitionDate}}'
WHERE schedule.agreement_id <> 1 /* fex_line 203 */
  AND agreement.product_code <> 'FLSMFI004'
),
invoice_totals AS (
  SELECT invoice.schedule_id,
    SUM(invoice.supplier_invoice_total_amount) AS supplier_invoice_total,
    MAX(invoice.payee_reference) AS payee_reference,
    MAX(invoice.supplier_invoice_currency_code) AS currency_code
  FROM fact_ap_reconciliation_supplier_invoice invoice
  INNER JOIN dim_payee payee /* fex_line 73 */
    ON invoice.payee_id = payee.payee_id
   AND payee.business_date = '{{PartitionDate}}'
  WHERE invoice.invoice_received_date <= CAST(COALESCE(NULLIF('{{StartDate}}', ''), '{{PartitionDate}}') AS DATE) /* fex_line 88 */
    AND payee.payee_segment_code = '{{PayeeSegment}}' /* fex_line 87 */
  GROUP BY invoice.schedule_id
), cash_totals AS (
  SELECT cash.schedule_id, SUM(cash.cash_allocation_amount) AS cash_total
  FROM fact_ap_reconciliation_cash_allocation cash
  WHERE cash.applied_date <= CAST(COALESCE(NULLIF('{{StartDate}}', ''), '{{PartitionDate}}') AS DATE) /* fex_line 50 */
  GROUP BY cash.schedule_id
), posting_totals AS (
  SELECT posting.schedule_id, SUM(posting.amount_base) AS posting_total
  FROM fact_ap_reconciliation_posting posting
  WHERE posting.posting_date <= CAST(COALESCE(NULLIF('{{StartDate}}', ''), '{{PartitionDate}}') AS DATE) /* fex_line 122 */
  GROUP BY posting.schedule_id
), matched AS (
  SELECT COALESCE(invoice.schedule_id, cash.schedule_id, posting.schedule_id) AS schedule_id,
    invoice.supplier_invoice_total, invoice.currency_code, invoice.payee_reference,
    cash.cash_total, posting.posting_total
  FROM invoice_totals invoice
  FULL OUTER JOIN cash_totals cash /* fex_line 130 */
    ON invoice.schedule_id = cash.schedule_id
  FULL OUTER JOIN posting_totals posting /* fex_line 146 */
    ON COALESCE(invoice.schedule_id, cash.schedule_id) = posting.schedule_id
), reconciled AS (
  SELECT matched.schedule_id, matched.supplier_invoice_total, matched.currency_code, matched.payee_reference, matched.cash_total, matched.posting_total,
    COALESCE(matched.supplier_invoice_total, 0) + COALESCE(matched.cash_total, 0) AS unpaid_amount,
    COALESCE(matched.supplier_invoice_total, 0) + COALESCE(matched.cash_total, 0)
      + COALESCE(matched.posting_total, 0) AS difference
  FROM matched
), eligible AS (
  SELECT reconciled.schedule_id, reconciled.supplier_invoice_total, reconciled.currency_code, reconciled.payee_reference, reconciled.cash_total, reconciled.posting_total, reconciled.unpaid_amount, reconciled.difference, schedule.schedule_ref, agreement.agreement_type, agreement.product,
    ROW_NUMBER() OVER (PARTITION BY schedule.schedule_ref ORDER BY reconciled.schedule_id DESC) AS schedule_rank
  FROM reconciled
  INNER JOIN dim_schedule schedule /* fex_line 180 */
    ON reconciled.schedule_id = schedule.schedule_id
   AND schedule.business_date = '{{PartitionDate}}'
  INNER JOIN dim_agreement agreement /* fex_line 183 */
    ON schedule.agreement_id = agreement.agreement_id
   AND agreement.business_date = '{{PartitionDate}}'
  WHERE reconciled.difference >= 0.01 OR reconciled.difference <= -0.01 /* fex_line 169 */
)
SELECT
  eligible.schedule_ref AS `Agreement number`, /* col 01, fex_line 222 */
  MAX(eligible.agreement_type) AS `Finance type`, /* col 02, fex_line 212 */
  MAX(eligible.product) AS `Product`, /* col 03, fex_line 213 */
  MAX(eligible.currency_code) AS `Inv.,currency,code`, /* col 04, fex_line 214 */
  SUM(eligible.supplier_invoice_total) AS `Supplier invoice amuount (incl. VAT)`, /* col 05, fex_line 215 */
  MAX(CASE WHEN eligible.schedule_rank = 1 THEN eligible.cash_total END) AS `Cashallocation amount`, /* col 06, fex_line 216 */
  SUM(eligible.unpaid_amount) AS `Unpaid Amount`, /* col 07, fex_line 217 */
  SUM(eligible.posting_total) AS `Postings accounts:,2280+2564+2567+1890`, /* col 08, fex_line 218 */
  SUM(eligible.difference) AS `Difference`, /* col 09, fex_line 219 */
  MAX(eligible.payee_reference) AS `Payee reference` /* col 10, fex_line 220 */
FROM eligible
GROUP BY eligible.schedule_ref",

    Replacements = {
        {"{{PartitionDate}}",     pPartitionDate},
        {"{{SourceSchema}}",      pSourceSchema},
        {"{{SourceTablePrefix}}", pSourceTablePrefix},
        {"{{StartDate}}",         pStartDate},
        {"{{PayeeSegment}}",      pPayeeSegment}
    },
    Sql = List.Accumulate(Replacements, SqlTemplate, (s, r) => Text.Replace(s, r{0}, r{1})),

    // safety net: every token must have been replaced
    SqlChecked = if Text.Contains(Sql, "{{") then error "Unreplaced token left in SQL" else Sql,

    // ---- run against Impala ------------------------------------------------
    Source = Odbc.Query(ConnectionString, SqlChecked),

    Typed = Table.TransformColumnTypes(Source, {
        {"Agreement number", type text},
        {"Finance type", type text},
        {"Product", type text},
        {"Inv.,currency,code", type text},
        {"Supplier invoice amuount (incl. VAT)", type number},
        {"Cashallocation amount", type number},
        {"Unpaid Amount", type number},
        {"Postings accounts:,2280+2564+2567+1890", type number},
        {"Difference", type number},
        {"Payee reference", type text}
    })
in
    Typed
