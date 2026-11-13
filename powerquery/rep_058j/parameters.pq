// Create each of these as its own query in Power Query
// (Home > Manage Parameters > New Parameter does the same thing via the UI).
// Query names must match exactly: PartitionDate, SourceTablePrefix.

// ---- query: PartitionDate ----
#date(2026, 11, 10) meta [IsParameterQuery = true, Type = "Date", IsParameterQueryRequired = true]

// ---- query: SourceTablePrefix ----
// IsParameterQueryRequired = false so an empty prefix is allowed.
"one_int_" meta [IsParameterQuery = true, Type = "Text", IsParameterQueryRequired = false]
