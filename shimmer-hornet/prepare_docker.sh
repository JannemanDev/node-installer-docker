#!/bin/bash
set -e
source ../common/scripts/prepare_docker_functions.sh

check_env
elevate_to_root

source $(dirname "${0}")/.env

scriptDir=$(dirname "${0}")
dataDir="${HORNET_DATA_DIR:-$scriptDir/data}"
configFilenameInContainer="config.json"
configFilename="config-${HORNET_NETWORK:-mainnet}.json"
configPath="${dataDir}/config/${configFilename}"

validate_ssl_config "HORNET_SSL_CERT" "HORNET_SSL_KEY"
copy_common_assets

# Validate HORNET_NETWORK config
if [[ ! -z ${HORNET_NETWORK} ]] && [[ "${HORNET_NETWORK}" != "mainnet" ]] && [[ "${HORNET_NETWORK}" != "testnet" ]]; then
  echo "Invalid HORNET_NETWORK: ${HORNET_NETWORK}"
  exit 255
fi

prepare_data_dir "${dataDir}" \
                 "config" \
                 "storage/${HORNET_NETWORK:-mainnet}" \
                 "p2pstore/${HORNET_NETWORK:-mainnet}" \
                 "snapshots/${HORNET_NETWORK:-mainnet}" \
                 "indexer/${HORNET_NETWORK:-mainnet}" \
                 "participation/${HORNET_NETWORK:-mainnet}" \
                 "dashboard/${HORNET_NETWORK:-mainnet}" \
                 "prometheus" \
                 "grafana" \
                 "letsencrypt"

create_docker_network "shimmer"

# Generate config
if [[ -z ${HORNET_NETWORK} ]] || [ "${HORNET_NETWORK}" == "mainnet" ]; then
  extract_file_from_image "iotaledger/hornet" "${HORNET_VERSION}" "/app/${configFilenameInContainer}" "${configPath}"
else
  configUrl="https://raw.githubusercontent.com/iotaledger/node-docker-setup/main/stardust/config_testnet.json"
  echo "Downloading ${HORNET_NETWORK} config from ${configUrl}..."
  curl -L -s -o "${configPath}" "${configUrl}"
fi

echo "Adapting config with values from .env..."
set_config "${configPath}" ".node.alias"                  "\"${HORNET_NODE_ALIAS:-HORNET node}\""
set_config "${configPath}" ".p2p.bindMultiAddresses"      "[\"/ip4/0.0.0.0/tcp/${HORNET_GOSSIP_PORT:-15600}\", \"/ip6/::/tcp/${HORNET_GOSSIP_PORT:-15600}\"]"
set_config "${configPath}" ".p2p.autopeering.bindAddress" "\"0.0.0.0:${HORNET_AUTOPEERING_PORT:-14626}\""
set_config "${configPath}" ".db.path"                     "\"/app/storage\""
set_config "${configPath}" ".p2p.db.path"                 "\"/app/p2pstore\""
set_config "${configPath}" ".snapshots.fullPath"          "\"/app/snapshots/full_snapshot.bin\""
set_config "${configPath}" ".snapshots.deltaPath"         "\"/app/snapshots/delta_snapshot.bin\""
set_config "${configPath}" ".pruning.size.targetSize"     "\"${HORNET_PRUNING_TARGET_SIZE:-64GB}\""
set_config "${configPath}" ".p2p.autopeering.enabled"     "true"
set_config "${configPath}" ".restAPI.pow.enabled"         "${HORNET_POW_ENABLED:-true}"
set_config "${configPath}" ".prometheus.enabled"          "true"
set_config "${configPath}" ".prometheus.bindAddress"      "\"0.0.0.0:9311\""
set_config "${configPath}" ".inx.enabled"                 "true"
set_config "${configPath}" ".inx.bindAddress"             "\"0.0.0.0:9029\""
set_config "${configPath}" ".restAPI.jwtAuth.salt"        "\"${RESTAPI_SALT:-$(generate_random_string 80)}\"" "secret"

set_config_if_present_in_env "${configPath}" "HORNET_PRUNING_MAX_MILESTONES_TO_KEEP" ".pruning.milestones.maxMilestonesToKeep"
if [ ! -z "${HORNET_PRUNING_MAX_MILESTONES_TO_KEEP}" ]; then
  set_config "${configPath}" ".pruning.milestones.enabled" "true"
fi
rm -f "${tmp}"

echo "Finished"
