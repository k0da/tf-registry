#!/bin/bash
set -a
set -x
set -o pipefail
set -o errexit

GITHUB_TOKEN=$1
ARTIFACTS_DIR=$2
REPOSITORY=$3
BRANCH=$4
USERNAME=$5
EMAIL=$6
TARGET_DIR=$7
NAMESPACE=$8
GPG_KEYID=$9

run() {
  OWNER=$(cut -d '/' -f 1 <<< "$GITHUB_REPOSITORY")
  if [[ -z "$REPOSITORY" ]]; then
      REPOSITORY=$(cut -d '/' -f 2 <<< "$GITHUB_REPOSITORY")
  fi

  if [[ -z "$REPO_URL" ]]; then
      REPO_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${OWNER}/${REPOSITORY}"
  fi

  if [[ -z "$ARTIFACTS_DIR" ]]; then
      ARTIFACTS_DIR="artifacts"
  fi

  if [[ -z "$BRANCH" ]]; then
      BRANCH="gh-pages"
  fi

  if [[ -z "$TARGET_DIR" ]]; then
    TARGET_DIR="."
    WEB_ROOT="/"
  fi

  if [[ -z "$WEB_ROOT" ]]; then
    WEB_ROOT="/${TARGET_DIR}"
  fi


  if [[ -z "$NAMESPACE" ]]; then
    NAMESPACE=${REPOSITORY}
  fi

  if [[ -z "$REGISTRY_URL" ]]; then
      REGISTRY_URL="https://${OWNER}.github.io/${REPOSITORY}"
  fi

  if [[ -z "$COMMIT_USERNAME" ]]; then
      COMMIT_USERNAME="${GITHUB_ACTOR}"
  fi

  if [[ -z "$COMMIT_EMAIL" ]]; then
      COMMIT_EMAIL="${GITHUB_ACTOR}@users.noreply.github.com"
  fi

  init
  artifacts
  commit
}

init() {	
  git clone ${REPO_URL} pages
  pushd pages
  git checkout ${BRANCH}
  popd
  if [[ -f pages/$TARGET_DIR/terraform.json ]]; then
    return
  fi 
  pushd pages/$TARGET_DIR
  mkdir -p _data
  cp /data/terraform.json . 
  echo "path: $WEB_ROOT" > _data/root.yaml
  popd
}

artifacts() {
  tmp_dir=$(mktemp -d)
  pushd $ARTIFACTS_DIR
  for file in $(ls *.zip);do
    provider_file=${file#terraform-provider-*}
    provider=${provider_file%%.zip}
    read -r name version os arch <<<$(echo $provider | awk -F "_" '{print $1" "$2" "$3" "$4}')
    if [[ ! -f $tmp_dir/provider_current.json ]]; then
      cat << EOF > $tmp_dir/provider_current.json
[
  {"name": "$name",
  "version": "$version"}
]
EOF
    fi
    cat << EOF > $tmp_dir/${os}_${arch}.json
{ "os": "$os",
  "arch": "$arch"}
EOF
    jq --slurpfile arch $tmp_dir/${os}_${arch}.json '.[0].platforms += $arch' $tmp_dir/provider_current.json >> $tmp_dir/provider_current_updated.json
    mv $tmp_dir/provider_current_updated.json $tmp_dir/provider_current.json

    # Generate download.json
    mkdir -p ../pages/$NAMESPACE/$name/$version/download/$os
    cat << EOF > ../pages/$NAMESPACE/$name/$version/download/$os/$arch
{
  "protocols": [
  "5.1"
  ],
  "os": "$os",
  "arch": "$arch",
  "filename": "$file",
  "download_url": "https://media.githubusercontent.com/media/${OWNER}/${REPOSITORY}/${BRANCH}/download/$file",
  "shasums_url": "https://media.githubusercontent.com/media/${OWNER}/${REPOSITORY}/${BRANCH}/download/terraform-provider-${name}_${version}_SHA256SUMS",
  "shasums_signature_url": "https://media.githubusercontent.com/media/${OWNER}/${REPOSITORY}/${BRANCH}/download/terraform-provider-${name}_${version}_SHA256SUMS.sig",
  "shasum": "$(sha256sum $file | awk -F " " '{print $1}')",
  "signing_keys": {
    "gpg_public_keys": [
      { "key_id": "$(gpg -k --with-colons | grep "fpr:.*$GPG_KEYID" | awk -F ":" '{print $10}')",
	"ascii_armor": "$(gpg --armor --export $GPG_KEYID | sed -e ':a;N;$!ba;s/\n/\\n/g')"
      }
    ]
  }
}
EOF
    mkdir -p ../pages/download
    cp $file ../pages/download/
  done
  popd

  cp $ARTIFACTS_DIR/terraform-provider-${name}_${version}_SHA256SUMS pages/download/
  cp $ARTIFACTS_DIR/terraform-provider-${name}_${version}_SHA256SUMS.sig pages/download/
  if [[ -f pages/_data/providers.json ]]; then
    jq -s '.[0] + .[1]' pages/_data/providers.json $tmp_dir/provider_current.json
  else
    cp $tmp_dir/provider_current.json pages/_data/providers.json
  fi
  cp /data/versions pages/$TARGET_DIR/$NAMESPACE/$name/
}

commit() {
  pushd pages
  git lfs track 'download/*'
  git add .gitattributes
  git config user.name "${COMMIT_USERNAME}"
  git config user.email "${COMMIT_EMAIL}"
  git remote set-url origin ${REPO_URL}
  git add ${TARGET_DIR}
  git commit -m "Generate Terraform registry"
  git push origin ${BRANCH}
  popd
}

run
