#!/bin/bash
while getopts ":H:u:d:p:P:" opt; do
    case $opt in
    H)
        server=$OPTARG
        ;;
    u)
        user=$OPTARG
        ;;
    p)
        password=$OPTARG
        ;;
    d)
        db=$OPTARG
        ;;
    P)
        path=$OPTARG
        ;;
    :)
        echo "La opción -$OPTARG requiere un argumento."
        exit 1
        ;;
    \?)
        echo "Opción inválida: -$OPTARG"
        exit 1
        ;;
    esac
done

if [[ -z $server || -z $user || -z $password || -z $db || -z $path ]]; then
    echo "No se han suficientes parametros, por favor ejecute el script con la opción -h para ver la ayuda."
    exit 1
fi

# echo "Loading environment variables from .env file"
# TODO: Should we allow the use of an .env?
# export $(grep -v '^#' .env | xargs)

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')]: $1" >log
}

check_dependencies() {
    # log "Checking dependencies"
    if ! [ -x "$(command -v docker)" ]; then
        # log "Error: docker is not installed."
        echo "Error: docker is not installed."
        exit 1
    fi

    # if ! [ -x "$(command -v docker-compose)" ]; then
    #     # log "Error: docker-compose is not installed."
    #     echo "Error: docker is not installed."
    #     exit 1
    # fi

    # TODO: Should we use gum to check for dependencies?
    # if ! [ -x "$(command -v gum)" ]; then
    #     log "Error: gum is not installed."
    #     echo "Error: gum is not installed."
    #     exit 1
    # fi
}

check_dependencies

sqlproj="$path/$db.sqlproj"

# TODO: should we create the folder if it does not exist?
# if [ ! -d $path ]; then
#     echo "Folder $path does not exist, do you want me to create it? (y/n)"
#     read create
#     if [ $create = "y" ]; then
#         mkdir $path
#         echo "Folder $path created"
#     else
#         echo "Folder $path does not exist, exiting..."
#         exit 1
#     fi
# fi

echo "Runnin mssql-scripter to export database $db from server $server to folder $path"
docker run --rm -it -v $path/temp:/export ghcr.io/akrista/mssql-scripter mssql-scripter -S $server -U $user -P $password -d $db --exclude-use-database --exclude-headers --file-per-object --display-progress -f /export

echo "
Changing file permissions, you may need to enter your password"
sudo chown -R $USER:$USER $path/temp

for file in $path/temp/*; do
    if [[ -f $file ]]; then
        iconv -f UTF-16LE -t UTF-8 $file >$file.tmp
        mv $file.tmp $file
    fi
done

rm $path/temp/*.Database.sql

declare -a schemas
declare -a exportedSchema

sqlprojItems=$(sed -n 's/.*<Build Include="\([^"]*\).*/\1/p' $sqlproj | tr '\\' '/')

while IFS= read -r linea; do
    sqlprojList+=("$linea")
done <<<"$sqlprojItems"

for file in $(find $path/temp/ -name "*.sql"); do
    filename=$(basename $file)
    count=$(echo $filename | tr -cd '.' | wc -c)

    if [ $count -ge 3 ]; then
        schema=$(echo $filename | cut -d '.' -f 1)

        if [[ ! " ${schemas[@]} " =~ " ${schema} " ]]; then
            schemas+=("$schema")
        fi
    fi
done

for schema in "${schemas[@]}"; do
    mkdir -p $path/temp/$schema/Functions
    mkdir -p $path/temp/$schema/Stored\ Procedures
    mkdir -p $path/temp/$schema/Tables
    mkdir -p $path/temp/$schema/Views

    for file in $(find $path/temp/ -name "$schema.*.sql"); do
        filename=$(basename $file)
        extension=$(echo $filename | cut -d '.' -f 3)
        objectName=$(echo $filename | cut -d '.' -f 2)

        if [ $extension = "Table" ]; then

            # TODO: This is a workaround to remove the first 2 lines of the file, we should find a better way to do this
            # for string in "SET ANSI_NULLS ON" "SET ANSI_NULLS OFF" "QUOTED_IDENTIFIER ON" "QUOTED_IDENTIFIER OFF"; do
            #     if grep -q "$string" $file; then
            #         tail -n +2 $file >$file.tmp
            #         mv $file.tmp $file
            #         if grep -q "GO" $file; then
            #             tail -n +2 $file >$file.tmp
            #             mv $file.tmp $file
            #         fi
            #     fi
            # done

            mv $file $path/temp/$schema/Tables/$objectName.sql
            exportedSchema+=("$path/temp/$schema/Tables/$objectName.sql")
        elif [ $extension = "View" ]; then
            mv $file $path/temp/$schema/Views/$objectName.sql
            exportedSchema+=("$path/temp/$schema/Views/$objectName.sql")
        elif [ $extension = "UserDefinedFunction" ]; then
            mv $file $path/temp/$schema/Functions/$objectName.sql
            exportedSchema+=("$path/temp/$schema/Functions/$objectName.sql")
        elif [ $extension = "StoredProcedure" ]; then
            mv $file $path/temp/$schema/Stored\ Procedures/$objectName.sql
            exportedSchema+=("$path/temp/$schema/Stored Procedures/$objectName.sql")
        fi
    done
done

mkdir -p $path/temp/Security

for file in $(find $path/temp/ -name "*.sql"); do
    filename=$(basename $file)
    extension=$(echo $filename | cut -d '.' -f 2)
    objectName=$(echo $filename | cut -d '.' -f 1)

    if [ $extension = "User" ]; then
        mv $file $path/temp/Security/$objectName.sql
        exportedSchema+=("$path/temp/Security/$objectName.sql")
    elif [ $extension = "Schema" ]; then
        mv $file $path/temp/Security/$objectName.sql
        exportedSchema+=("$path/temp/Security/$objectName.sql")
    fi
done

normalizedSqlprojList=()
for element in "${sqlprojList[@]}"; do
    normalizedElement="${element#"$path"}"
    normalizedSqlprojList+=("$normalizedElement")
done

normalizedExportedSchema=()
for element in "${exportedSchema[@]}"; do
    normalizedElement="${element#"$path/temp/"}"
    normalizedExportedSchema+=("$normalizedElement")
done

additionalElements=()
for element in "${normalizedExportedSchema[@]}"; do
    if [[ ! " ${normalizedSqlprojList[@]} " =~ " $element " ]]; then
        additionalElements+=("$element")
    fi
done

if [ ! -d "$path/Changelogs" ]; then
    mkdir "$path/Changelogs"
fi

now=$(date +"%d%m%Y%H%M%S")
changelogFile="$path/Changelogs/$now.md"

countModified=0
countAdded=0
countDeleted=0

for file in "${normalizedSqlprojList[@]}"; do
    if [ -f "$path/$file" ] && [ -f "$path/temp/$file" ]; then
        if ! cmp -s "$path/$file" "$path/temp/$file"; then
            countModified=$((countModified + 1))
        fi
    fi
done

for file in "${additionalElements[@]}"; do
    if [ -f "$path/temp/$file" ]; then
        countAdded=$((countAdded + 1))
    fi
done

for file in "${normalizedSqlprojList[@]}"; do
    if [ ! -f "$path/temp/$file" ]; then
        countDeleted=$((countDeleted + 1))
    fi
done

echo "Cantidad de archivos a modificar: $countModified" >$changelogFile
echo "Archivos a modificar:" >>$changelogFile
for file in "${normalizedSqlprojList[@]}"; do
    if [ -f "$path/$file" ] && [ -f "$path/temp/$file" ]; then
        if ! cmp -s "$path/$file" "$path/temp/$file"; then
            cp "$path/temp/$file" "$path/$file"
            echo "- $file" >>$changelogFile
        fi
    fi
done

echo "Cantidad de archivos a agregar: $countAdded" >>$changelogFile
echo "Archivos a agregar:" >>$changelogFile
for file in "${additionalElements[@]}"; do
    if [ -f "$path/temp/$file" ]; then
        lastBuildLine=$(grep -n '<Build Include=' $sqlproj | tail -n 1 | cut -d ":" -f 1)
        escapedFile=$(sed 's/[][\.^$*+?{}()|\/]/\\&/g' <<<"$file" | sed 's/\//\\\\/g')
        sed -i "${lastBuildLine} a \ \ \ \ <Build Include=\"$escapedFile\" />" $sqlproj
        cp "$path/temp/$file" "$path/$file"
        echo "- $file" >>$changelogFile
    fi
done

echo "Cantidad de archivos a eliminar: $countDeleted" >>$changelogFile
echo "Archivos a eliminar:" >>$changelogFile
for file in "${normalizedSqlprojList[@]}"; do
    if [ ! -f "$path/temp/$file" ]; then
        escapedFile=$(sed 's/[][\.^$*+?{}()|\/]/\\&/g' <<<"$file" | sed 's/\//\\\\/g')
        sed -i "/<Build Include=\"$escapedFile\" \/>/d" $sqlproj
        rm -f "$path/$file"
        echo "- $file" >>$changelogFile
    fi
done

rm -rf "$path/temp"
