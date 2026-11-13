// =====================================================================
// Portfolio 4 : MongoDB queries, indexes and explain plans
//
// Run these in MongoDB Compass. Open the `nou` database, select the
// `learner_engagement` collection, then:
//   - find() queries   -> the FILTER bar on the Documents tab
//   - aggregations     -> the Aggregations tab (paste the array)
//   - createIndex()    -> the Indexes tab, or the embedded mongosh
//                         (the ">_ MONGOSH" bar at the bottom of Compass)
//
// The collection holds 33,024 learner documents with 214,656 advisor
// interactions embedded inside them.
// =====================================================================


// ---------------------------------------------------------------------
// Q1. The single-read lookup -- the whole argument for the document model
// ---------------------------------------------------------------------
// In PostgreSQL this answer requires joining enrolment, application,
// applicant, cohort, programme, faculty, channel, staff and
// advisor_interaction -- nine tables. Here it is one document.

db.learner_engagement.find({ _id: "NOU/2026/0000001" })


// ---------------------------------------------------------------------
// Q2. Advisor workload and reach rate
// ---------------------------------------------------------------------
db.learner_engagement.aggregate([
  { $unwind: "$interactions" },
  { $group: {
      _id: { advisor: "$enrolment.advisor", staff_no: "$enrolment.advisor_no" },
      interactions: { $sum: 1 },
      successful: { $sum: { $cond: [
          { $in: ["$interactions.outcome", ["reached", "resolved"]] }, 1, 0 ] } },
      total_seconds: { $sum: "$interactions.duration_seconds" }
  }},
  { $project: {
      _id: 0,
      advisor: "$_id.advisor",
      staff_no: "$_id.staff_no",
      interactions: 1,
      successful: 1,
      reach_pct: { $round: [ { $multiply: [
          { $divide: ["$successful", "$interactions"] }, 100 ] }, 2 ] },
      avg_minutes: { $round: [ { $divide: [
          { $divide: ["$total_seconds", "$interactions"] }, 60 ] }, 1 ] }
  }},
  { $sort: { interactions: -1 } }
])


// ---------------------------------------------------------------------
// Q3. Monthly contact volume by channel of contact
// ---------------------------------------------------------------------
db.learner_engagement.aggregate([
  { $unwind: "$interactions" },
  { $group: {
      _id: { month: "$interactions.year_month", mode: "$interactions.mode" },
      contacts: { $sum: 1 }
  }},
  { $sort: { "_id.month": 1, contacts: -1 } }
])


// ---------------------------------------------------------------------
// Q4. At-risk learners: active, but barely contacted
// ---------------------------------------------------------------------
// interaction_count is pre-computed at export time. Storing a derived
// value alongside the array it summarises is normal in a document store
// and is the same trade-off as cohort.seats_taken in Portfolio 1.

db.learner_engagement.aggregate([
  { $match: { "enrolment.status": "active", interaction_count: { $lt: 3 } } },
  { $project: {
      _id: 1,
      learner: { $concat: ["$name.first", " ", "$name.last"] },
      intake: "$cohort.intake_code",
      programme: "$programme.code",
      advisor: "$enrolment.advisor",
      interaction_count: 1,
      reached_count: 1
  }},
  { $sort: { interaction_count: 1, _id: 1 } }
])


// ---------------------------------------------------------------------
// Q5. Acquisition channel against enrolment outcome
// ---------------------------------------------------------------------
db.learner_engagement.aggregate([
  { $group: {
      _id: { channel: "$acquisition_channel", status: "$enrolment.status" },
      learners: { $sum: 1 }
  }},
  { $group: {
      _id: "$_id.channel",
      total: { $sum: "$learners" },
      breakdown: { $push: { status: "$_id.status", n: "$learners" } }
  }},
  { $sort: { total: -1 } }
])


// =====================================================================
// INDEXES AND EXPLAIN
// =====================================================================

// ---------- BEFORE: collection scan ----------
// Run this first, with no indexes beyond the automatic _id index.
// Record totalDocsExamined and executionTimeMillis.

db.learner_engagement.find(
  { "enrolment.advisor_no": "NOU-S-0045", "enrolment.status": "active" }
).explain("executionStats")

// Expect: stage COLLSCAN, totalDocsExamined 33024.


// ---------- Create the indexes ----------

// Supports the advisor caseload query above.
db.learner_engagement.createIndex(
  { "enrolment.advisor_no": 1, "enrolment.status": 1 },
  { name: "idx_advisor_status" }
)

// Supports cohort reporting.
db.learner_engagement.createIndex(
  { "cohort.intake_code": 1, "enrolment.status": 1 },
  { name: "idx_intake_status" }
)

// A MULTIKEY index -- it indexes a field inside an embedded array.
// MongoDB creates one index entry per array element, so this one index
// has 214,656 entries across 33,024 documents. There is no relational
// equivalent of this: in PostgreSQL the interactions are a separate
// table and this would just be an ordinary index on that table.
db.learner_engagement.createIndex(
  { "interactions.outcome": 1 },
  { name: "idx_interaction_outcome_multikey" }
)

db.learner_engagement.getIndexes()


// ---------- AFTER: indexed lookup ----------
// Same query. Record the new numbers and compare.

db.learner_engagement.find(
  { "enrolment.advisor_no": "NOU-S-0045", "enrolment.status": "active" }
).explain("executionStats")

// Expect: stage IXSCAN using idx_advisor_status, totalDocsExamined
// equal to the number of matches rather than the whole collection.


// ---------- The multikey index in use ----------
db.learner_engagement.find(
  { "interactions.outcome": "escalated" }
).explain("executionStats")

// Note what this returns: whole learner documents that contain AT LEAST
// ONE escalated interaction. It does not return the interactions
// themselves. Filtering inside the array needs $unwind plus $match, or
// $filter in a $project -- which is one of the real costs of embedding.
