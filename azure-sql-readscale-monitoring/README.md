# Goal
This sample shows how to collect resource utilization and performance data from a secondary (aka read-only, aka read-scale) replica in Azure SQL DB Business Critical service tier, and persist this data in an Azure SQL DB database.

# Description
The **setup-read-scale-secondary-telemetry.sql** script creates objects to be used for monitoring. Objects are created on the read-write primary replica, and exist on all replicas of the database.

A client, such as an Azure Automation runbook or an Azure Functions application, connects to the secondary replica of the database to be monitored using _ApplicationIntent=ReadOnly_ in the connection string.

The client periodically executes stored procedures that collect telemetry data from DMVs, and load that data into tables on the read-write primary replica of the same database, or the read-write replica of another database, using the _sys.sp_execute_remote_ stored procedure.

Each stored procedure on the secondary may be executed on a different schedule depending on required data latency and sampling rate.

The current sample collects data from two DMVs: 
- sys.dm_db_resource_stats (resource utilization statistics).
- sys.dm_database_replica_states (replica diagnostics, such as redo queue size).

The sample can be further extended to collect data from additional DMVs by creating additional stored procedure pairs.

# Requirements
- The _Allow Azure services and resources to access this server_ option at the Azure SQL server level must be enabled. This is required for the _sys.sp_execute_remote_ call on the secondary to connect to the primary. Alternatively, a database-level firewall rule allowing traffic from 0.0.0.0 must exist in the monitored database.
- The principal used by the client to connect to the read-only replica must be granted EXECUTE permission on the _telemetry_ schema.

# Setup
Make the following changes in the **setup-read-scale-secondary-telemetry.sql** script, and execute it on the primary read-write replica of the database to be monitored:
- Change literal values for LOCATION and DATABASE_NAME in the CREATE EXTERNAL DATA SOURCE statement to reflect the server and database to be monitored. The sample assumes that data will be loaded into the database being monitored.
- Replace both _replace-with-complex-password_ placeholders with an actual complex password.

# Testing
The **test-read-scale-secondary-telemetry.sql** script can be used to test the sample.
