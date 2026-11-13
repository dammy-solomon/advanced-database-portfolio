// =====================================================================
// Portfolio 5 / Part 2 : replication and consistency on MongoDB Atlas
//
// Run in Compass -> "Open MongoDB shell".
//
// The Atlas M0 free tier is a THREE-NODE REPLICA SET, not a single
// server. That is what makes it usable as distributed-systems evidence
// rather than just "a database in the cloud".
// =====================================================================


// ---------------------------------------------------------------------
// 1. Prove the topology
// ---------------------------------------------------------------------
db.hello()

// In the output, look for:
//   setName      - the replica set name (e.g. atlas-k0jbmx-shard-0)
//   hosts        - THREE hostnames; these are the three members
//   primary      - which member is currently accepting writes
//   isWritablePrimary / secondary - the role of the node you are on
//   me           - the node actually serving this connection
//
// The Compass shell prompt also shows it directly:
//   Atlas atlas-xxxxx-shard-0 [primary] nou>
//
// SCREENSHOT the hosts array and the prompt.


// ---------------------------------------------------------------------
// 2. Full replica set status
// ---------------------------------------------------------------------
rs.status()

// This was expected to fail on M0 with "not authorized on admin to
// execute command", since managed free tiers usually restrict
// administrative commands. It does not fail - the full status is
// readable.
//
// Look for:
//   votingMembersCount: 3   - three full voting members
//   majorityVoteCount: 2    - what "majority" actually means here
//   heartbeatIntervalMillis - how often members check each other
//   term                    - the election term; 150 at time of capture
//
// What M0 withholds is control, not visibility: reconfiguring members,
// forcing stepdowns and tuning election priorities are blocked.
//
// SCREENSHOT the output.


// ---------------------------------------------------------------------
// 3. Write concern : how many nodes must acknowledge a write
// ---------------------------------------------------------------------
// w:1 - the primary alone acknowledges. Fast. If the primary fails
// before replicating, the write can be lost.
db.learner_engagement.updateOne(
  { _id: "NOU/2026/0000001" },
  { $set: { "engagement_flag": "reviewed_w1" } },
  { writeConcern: { w: 1 } }
)

// w:"majority" - a majority of the three nodes must confirm before the
// write is acknowledged. Slower, but survives the loss of any one node.
db.learner_engagement.updateOne(
  { _id: "NOU/2026/0000001" },
  { $set: { "engagement_flag": "reviewed_majority" } },
  { writeConcern: { w: "majority", wtimeout: 5000 } }
)

// This is the durability dial. It is a per-operation choice, which
// matters: a learner's acceptance payment should use "majority"; a
// click-tracking event does not need to.


// ---------------------------------------------------------------------
// 4. Read concern : what you are allowed to see
// ---------------------------------------------------------------------
// "local" - whatever this node has, which may not yet be committed
// across the set.
db.learner_engagement.find({ _id: "NOU/2026/0000001" })
  .readConcern("local")

// "majority" - only data acknowledged by a majority, so it cannot be
// rolled back by a failover.
db.learner_engagement.find({ _id: "NOU/2026/0000001" })
  .readConcern("majority")


// ---------------------------------------------------------------------
// 5. Read preference : which node answers
// ---------------------------------------------------------------------
// Reading from a secondary spreads load, but secondaries lag the
// primary by replication delay. This is eventual consistency made
// concrete: the same query on two nodes can return different answers
// for a short window after a write.
db.learner_engagement.find({ _id: "NOU/2026/0000001" })
  .readPref("secondaryPreferred")

// For NOU this is the right setting for the engagement dashboard
// (a few seconds of staleness is harmless) and the wrong setting for
// checking whether a learner has paid.


// ---------------------------------------------------------------------
// 6. Clean up the demonstration field
// ---------------------------------------------------------------------
db.learner_engagement.updateOne(
  { _id: "NOU/2026/0000001" },
  { $unset: { engagement_flag: "" } }
)
