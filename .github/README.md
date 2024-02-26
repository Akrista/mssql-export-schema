# MSSQL Export Schema

This project is mostly a test of concept(?) and experimental. Inspired on the functionalities of [SSDT](https://learn.microsoft.com/en-us/sql/ssdt/sql-server-data-tools?view=sql-server-ver16), the idea is to check if is possible to replicate the feature used on SSDT to compare a Database with an .sqlproj and then update the Schema of said .sqlproj with the differences encountered on the Database.

## Dependencies

This shell script only has been tested on Linux as it uses several [core-utils](https://es.wikipedia.org/wiki/GNU_Core_Utilities) tools, besides that, we use [Docker](https://docs.docker.com/manuals/) to run [mssql-scripter](https://github.com/microsoft/mssql-scripter); this is to ensure a working enviroment for a longer time, as it seems that microsoft [abandoned mssql-scripter on 2022](https://github.com/microsoft/mssql-scripter/issues/236#issuecomment-824553254).

Besides these comments, i'm kinda [working on maintaining](https://github.com/notakrista/ssdt-cli) a fork of mssql-scripter and add this compare-database-sqlproj feature to the cli tool (but don't get your hopes up).

## Get Started

Just run the `.sh` file, this file will run a docker container with an image of mssql-scripter that will export the schema of a selected Database to a `temp` directory on a selected `path`, then it will compare the exported schema with the one existing on your .sqlproj on the root of the selected `path`. Finally, the script will generate a changelod.md file with the files to be modified, added and removed, and proceed to replace, add or remove those scripts on the `path`

Ensure that you pass the following parameters to run the shell script:

```console
bash .sh -u user -p password -d yourDatabase -H localhost.or.the.host -P /directory/where/the/sqlproj/resides
```

!!!IMPORTANT!!! I tried my best to ensure (kinda) that the schema used by the exported if similar to the one used by SSDT, nonetheless, it has the following catches (or at least these are the ones i detected so far):

- Doesn't add the corresponding GRANTs to every .sql script
- Sometimes the format is not the same as the one provided by SSDT
- The exported .sql always uses `SET ANSI_NULLS ON` and `SET QUOTED_IDENTIFIER ON` on every operation
- SSDT sometimes seems to not detect changes on names of objects on the .sqlproj, here, the script so far ensures that if the object name on the schema is different, it will updated it
- RoleMemberships is dismissed for some reason...

Finally, i tried to emulate the schema used by SSDT, not the one used by [ADS(Azure Data Studio)](https://github.com/microsoft/azuredatastudio); while they support some of the features of SSDT, the .sqlproj generated seems not to be compatible with the one used by the schema compare of SSDT (also, for some reason ADS doesn't offer a CLI option of their schema compare).
