#!/usr/bin/env sh
#
# Sifnode migration (from Cosmos 0.39.x to 0.4x.x).
#

#
# Usage.
#
usage() {
  cat <<- EOF
  Usage: $0 [OPTIONS]

  Options:
  -h      This help output.
  -c      New Chain ID.
  -s      Cosmos SDK target version.
  -t      Genesis time (in UTC).
  -v      The new sifnoded binary version.
  -z      Data migrate version.

EOF
  exit 1
}

#
# Setup
#
setup() {
  set_chain_id "${1}"
  set_cosmos_sdk_version "${2}"
  set_genesis_time "${3}"
  set_version "${4}"
  set_data_migrate_version "${5}"
  create_export_state_dir
}

#
# Already upgraded?
#
upgraded() {
  if [ -f "${HOME}"/.sifnoded/."${COSMOS_SDK_VERSION}"_upgraded ]; then
    exit 0
  fi
}

#
# Set Chain ID.
#
set_chain_id() {
  CHAIN_ID=${1:-"sifchain-1"}
}

#
# Set Genesis time.
#
set_cosmos_sdk_version() {
  COSMOS_SDK_VERSION=${1:-"0.40"}
}

#
# Set Genesis time.
#
# date -u +"%Y-%m-%dT%H:%M:%SZ"
#
set_genesis_time() {
  GENESIS_TIME=${1}
}

#
# Set version.
#
set_version() {
  VERSION=${1}
}

#
# Set data migrate version.
#
set_data_migrate_version() {
  DATA_MIGRATE_VERSION=${1:-"0.9"}
}

#
# Create export state dir.
#
create_export_state_dir() {
  EXPORT_STATE_DIR="${HOME}"/.sifnoded/"${COSMOS_SDK_VERSION}"_exports
  mkdir "${EXPORT_STATE_DIR}"
}

#
# Backup.
#
backup() {
  BACKUP_DIR="${HOME}"/.sifnoded/backups/$(date +%s%N)/
  mkdir -p "${BACKUP_DIR}"
  cp -avr "${HOME}"/.sifnoded/data/ "${BACKUP_DIR}"
  cp -avr "${HOME}"/.sifnoded/config/ "${BACKUP_DIR}"
}

#
# Export state.
#
export_state() {
  "${HOME}"/.sifnoded/cosmovisor/current/bin/sifnoded export > "${EXPORT_STATE_DIR}"/exported_state.json
}

#
# Migrate exported state.
#
migrate_exported_state() {
  # Need to be the latest binary.
  # COSMOS_SDK_VERSION == 0.40
  "${HOME}"/.sifnoded/cosmovisor/upgrades/"${VERSION}"/bin/sifnoded migrate v"${COSMOS_SDK_VERSION}" "${EXPORT_STATE_DIR}"/exported_state.json \
    --chain-id "${CHAIN_ID}" \
    --genesis-time "${GENESIS_TIME}" > "${EXPORT_STATE_DIR}"/migrated_state.json \
    --log_level fatal

  # Removes the message that Cosmos prints about consensus_params.evidence.max_bytes
  sed -i '1d' "${EXPORT_STATE_DIR}"/migrated_state.json
}

#
# Migrate data.
#
migrate_data() {
  "${HOME}"/.sifnoded/cosmovisor/upgrades/"${VERSION}"/bin/sifnoded migrate-data v"${DATA_MIGRATE_VERSION}" "${EXPORT_STATE_DIR}"/migrated_state.json \
    --log_level info > "${EXPORT_STATE_DIR}"/migrated_data.json
}

#
# Configure IBC
#
configure_ibc() {
  cat "${EXPORT_STATE_DIR}"/migrated_data.json | jq '.app_state |= . + {"ibc":{"client_genesis":{"clients":[],"clients_consensus":[],"create_localhost":false},"connection_genesis":{"connections":[],"client_connection_paths":[]},"channel_genesis":{"channels":[],"acknowledgements":[],"commitments":[],"receipts":[],"send_sequences":[],"recv_sequences":[],"ack_sequences":[]}},"transfer":{"port_id":"transfer","denom_traces":[],"params":{"send_enabled":false,"receive_enabled":false}},"capability":{"index":"1","owners":[]}}' > "${EXPORT_STATE_DIR}"/genesis_ibc.json
  mv "${EXPORT_STATE_DIR}"/genesis_ibc.json "${EXPORT_STATE_DIR}"/genesis.json
}

#
# Reset old state.
#
reset_old_state() {
  "${HOME}"/.sifnoded/cosmovisor/upgrades/"${VERSION}"/bin/sifnoded unsafe-reset-all --log_level info
}

#
# Install genesis.
#
install_genesis() {
  cp "${EXPORT_STATE_DIR}"/genesis.json "${HOME}"/.sifnoded/config/genesis.json
}

#
# Update config.
#
update_config() {
  wget -O "${HOME}"/.sifnoded/config/app.toml https://raw.githubusercontent.com/Sifchain/networks/master/config/"${CHAIN_ID}"/app.toml

  # Fix the log level.
  sed -ri 's/log_level.*/log_level = \"info\"/g' "${HOME}"/.sifnoded/config/config.toml
}

#
# Update symlink
#
update_symlink() {
  rm "${HOME}"/.sifnoded/cosmovisor/current
  ln -s "${HOME}"/.sifnoded/cosmovisor/upgrades/"${VERSION}" "${HOME}"/.sifnoded/cosmovisor/current
}

#
# Completed.
#
completed() {
  touch "${HOME}"/.sifnoded/."${COSMOS_SDK_VERSION}"_upgraded
}

#
# Run.
#
run() {
  # Setup.
  #printf "\nConfiguring environment for upgrade..."
  setup "${1}" "${2}" "${3}" "${4}" "${5}"

  # Backup.
  #printf "\nTaking a backup..."
  backup

  # Check if already upgraded?
  printf "\nChecking if validator has already been upgraded..."
  upgraded

  # Export state.
  #printf "\nExporting the current state..."
  export_state

  # Migrate exported state.
  printf "\nMigrating the exported state..."
  migrate_exported_state

  # Migrate data.
  printf "\nMigrating data..."
  migrate_data

  # Configure IBC.
  printf "\nConfiguring IBC..."
  configure_ibc

  # Reset old state.
  printf "\nResetting old state..."
  reset_old_state

  # Install the new genesis.
  printf "\nInstalling the new genesis file..."
  install_genesis

  # Updating the config.
  printf "\nUpdating the node config (api,grpc,state-sync)..."
  update_config

  # Update symlink.
  printf "\nUpdating the cosmovisor symlink..."
  update_symlink

  # Complete.
  printf "\nUpgrade complete! Good luck!\n\n"
  completed
}

# Check the supplied opts.
while getopts ":hc:s:t:v:z:" o; do
  case "${o}" in
    h)
      usage
      ;;
    c)
      c=${OPTARG}
      ;;
    s)
      s=${OPTARG}
      ;;
    t)
      t=${OPTARG}
      ;;
    v)
      v=${OPTARG}
      ;;
    z)
      z=${OPTARG}
      ;;
    *)
      usage
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${c}" ]; then
  usage
fi

if [ -z "${s}" ]; then
  usage
fi

if [ -z "${t}" ]; then
  usage
fi

if [ -z "${v}" ]; then
  usage
fi

if [ -z "${z}" ]; then
  usage
fi

# Run.
run "${c}" "${s}" "${t}" "${v}" "${z}"
