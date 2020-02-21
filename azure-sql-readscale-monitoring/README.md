# Goal

This sample shows how to collect resource utilization and performance data from a secondary (aka read-only, aka read-scale) replica in Azure SQL DB Premium, Business Critical, and Hyperscale service tiers, and persist this data in an Azure SQL DB database.

# Description

The **setup-read-scale-secondary-telemetry.sql** script creates objects to be used for monitoring. Objects are created on the read-write primary replica, and exist on all replicas of the database.

A client, such as an Azure Automation runbook or an Azure Functions application, connects to the secondary replica(s) of the database to be monitored, using *ApplicationIntent=ReadOnly* in the connection string.

The client periodically executes stored procedures that collect telemetry data from DMVs, and load that data into tables on the read-write primary replica of the same database, or the read-write replica of another database, using the *sys.sp_execute_remote* stored procedure.

Each stored procedure on the secondary may be executed on a different schedule depending on required data latency and sampling rate.

This sample collects data from two DMVs:

- *sys.dm_db_resource_stats* (resource utilization statistics).
- *sys.dm_database_replica_states* (replica diagnostics, such as redo queue size). Only applicable to Premium and Business Critical databases.

The sample can be further extended to collect data from additional DMVs by creating additional stored procedure pairs.

# Requirements

- The *Allow Azure services and resources to access this server* option at the Azure SQL server level must be enabled. This is required for the *sys.sp_execute_remote* call on the secondary to connect to the primary. Alternatively, a database-level firewall rule allowing traffic from 0.0.0.0 must exist in the monitored database.
- The setup script must be executed by a member of *db_owner* role for the target database, or by a server administrator.
- The principal used by the client to connect to the read-only replica must be granted EXECUTE permission on the *telemetry* schema.
- For Hyperscale, the *GLOBAL_TEMPORARY_TABLE_AUTO_DROP* [database-scoped configuration](https://docs.microsoft.com/sql/t-sql/statements/alter-database-scoped-configuration-transact-sql) should be set to *OFF*.

# Setup

Make the following changes in the **setup-read-scale-secondary-telemetry.sql** script:

- Change the placeholders for LOCATION and DATABASE_NAME in the CREATE EXTERNAL DATA SOURCE statement to reflect the server and database to be monitored. The sample assumes that data will be loaded into the database being monitored.
- Replace both *replace-with-complex-password* placeholders with an actual complex password.

Execute the script on the primary read-write replica of the database to be monitored.

# Testing

The **test-read-scale-secondary-telemetry.sql** script can be used to test the sample.
