# Goal

This sample shows how to collect periodic snapshots of performance counters from an Azure SQL DB database and persist this data in a table.

# Description

There are two variants of the sample:

1. The **collect-azure-sql-performance-counters.sql** script collects data and writes it to a table in the same database.
2. The **collect-azure-sql-performance-counters-remote.sql** script collects data in a remote database and writes it to a table locally. 

The second ("remote") script requires a remote table to be created in the local database where the script executes, and where data is stored. This is done using the **set-up-remote-performance-counter-collection.sql** script.

# Requirements

- The principal used to execute the script must have the VIEW DATABASE STATE, CREATE TABLE, and INSERT permissions on the database.
- For remote collection, the *Allow Azure services and resources to access this server* option for the Azure SQL server hosting the remote database must be enabled. Alternatively, a database-level firewall rule allowing traffic from 0.0.0.0 must exist in the remote database.
