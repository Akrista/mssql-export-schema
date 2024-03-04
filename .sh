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

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')]: $1" >log
}

check_dependencies() {
    if ! [ -x "$(command -v docker)" ]; then
        echo "Error: docker is not installed."
        exit 1
    fi
}

win_sanitize() {
    echo $1 | sed 's/[\\\/:?*<>|"]//g'
}

check_dependencies

sqlproj="$path/$db.sqlproj"
docker run --rm -v $path/temp:/export ghcr.io/akrista/mssql-scripter mssql-scripter -S $server -U $user -P $password -d $db --exclude-use-database --exclude-headers --file-per-object --display-progress -f /export

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
        sanitized=$(win_sanitize $objectName)
        if [ "$sanitized" != "$objectName" ]; then
            mv $file $path/temp/Security/$sanitized.sql
            exportedSchema+=("$path/temp/Security/$sanitized.sql")
        else
            mv $file $path/temp/Security/$objectName.sql
            exportedSchema+=("$path/temp/Security/$objectName.sql")
        fi
    elif [ $extension = "Schema" ]; then
        sanitized=$(win_sanitize $objectName)
        if [ "$sanitized" != "$objectName" ]; then
            mv $file $path/temp/Security/$sanitized.sql
            exportedSchema+=("$path/temp/Security/$sanitized.sql")
        else
            mv $file $path/temp/Security/$objectName.sql
            exportedSchema+=("$path/temp/Security/$objectName.sql")
        fi
    fi
done

find $path/temp/ -type f -exec sed -i 's/\r$//' {} \;

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
