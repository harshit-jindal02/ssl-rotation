#!/bin/bash

set -ex

goDaddySecret="$GODADDY_SECRET"
goDaddyKey="$GODADDY_KEY"

echo "$WINDOWS_SSH" > windows-ssh-priv.txt
chmod 600 windows-ssh-priv.txt

windowsPath="\\Users\\Administrator\\Desktop\\certificates\\"

if [ -z "$DRY_RUN" ]; then
    DRY_RUN=true
fi

function generateCertificate() {

    echo "Generating Certificates"

    mkdir -p lib_ssl etc_ssl log_dir
    goDaddyCredFile="etc_ssl/godaddy_credentials.ini"

    echo "dns_godaddy_secret = $goDaddySecret" > $goDaddyCredFile
    echo "dns_godaddy_key = $goDaddyKey" >> $goDaddyCredFile

    uid=$(id -u)

    if [ "$DRY_RUN" == "false" ]; then
        echo "Running docker command"
            docker run --rm -q \
            -v "$PWD"/lib_ssl:/var/lib/letsencrypt \
            -v "$PWD"/etc_ssl:/etc/letsencrypt \
            -v "$PWD"/log_dir:/var/log/letsencrypt \
            --user "$uid" \
            miigotu/certbot-dns-godaddy certbot certonly \
            --authenticator dns-godaddy \
            --dns-godaddy-credentials /etc/letsencrypt/godaddy_credentials.ini \
            --keep-until-expiring --non-interactive --expand \
            --agree-tos --email "admin@msmartpay.in" \
            -d msmartpay.in -d '*.msmartpay.in'
    else
        echo "Dry run is set, skipped certbot"
    fi

    echo "Certificate Generation Complete"
    echo ""

}

function copyFile() {

    sourceFile=$1
    targetFile="$windowsPath$2"

    echo "Parsing $2 file"
    echo "----------------------"

    ssh_opt=("-o" "StrictHostKeyChecking=no" "-i" "windows-ssh-priv.txt")

    output=$(ssh "${ssh_opt[@]}" Administrator@panel.msmartpay.in "CertUtil -hashfile ""$targetFile"" MD5" | awk "NR==2" | tr -d '\r')
    containsError=$(echo "$output" | grep "The system cannot find the file" || true)
    if [ -n "$containsError" ]; then
        echo "File not found on server"
    else
        echo -e "MD5 on Server\t\t: $output"
    fi

    out=$(openssl dgst -md5 "$sourceFile" | cut -f 2 -d " ")
    echo -e "MD5 on this machine\t: $out"

    if [ "$output" == "$out" ]; then
        echo "Both Hashes are same, skipping..."
    else
        echo "Proceeding with replacing file..."

        if [ "$DRY_RUN" == "false" ]; then
            scp "${ssh_opt[@]}" "$sourceFile" Administrator@panel.msmartpay.in:"$targetFile"
        else
            echo "Dry run is set, skipped"
        fi
    fi
    echo "Parsing $2 complete"
    #echo "---------------"
    echo ""
}

function nginxRestart() {
    echo "Restarting Nginx..."
    if [ "$DRY_RUN" == "false" ]; then
        ssh "${ssh_opt[@]}" Administrator@panel.msmartpay.in "net stop \"nginx\" && net start \"nginx\""
    else
        echo "Dry run is set, skipped"
    fi
    echo ""
}

generateCertificate

copyFile "etc_ssl/live/msmartpay.in/fullchain.pem" "fullchain.pem"
copyFile "etc_ssl/live/msmartpay.in/privkey.pem" "privkey.pem"

nginxRestart

echo "Certificate Renewal completed Successfully"
