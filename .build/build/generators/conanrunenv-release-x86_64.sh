script_folder="/workspace/attackathon-xrpl-lending-protocol/.build/build/generators"
echo "echo Restoring environment" > "$script_folder/deactivate_conanrunenv-release-x86_64.sh"
for v in GRPC_DEFAULT_SSL_ROOTS_FILE_PATH OPENSSL_MODULES
do
   is_defined="true"
   value=$(printenv $v) || is_defined="" || true
   if [ -n "$value" ] || [ -n "$is_defined" ]
   then
       echo export "$v='$value'" >> "$script_folder/deactivate_conanrunenv-release-x86_64.sh"
   else
       echo unset $v >> "$script_folder/deactivate_conanrunenv-release-x86_64.sh"
   fi
done

export GRPC_DEFAULT_SSL_ROOTS_FILE_PATH="/root/.conan2/p/grpc39a01891b8038/p/res/grpc/roots.pem"
export OPENSSL_MODULES="/root/.conan2/p/opense49aff703bef0/p/lib/ossl-modules"