script_folder="/workspace/attackathon-xrpl-lending-protocol/.build/build/generators"
echo "echo Restoring environment" > "$script_folder/deactivate_conanbuildenv-release-x86_64.sh"
for v in PATH LD_LIBRARY_PATH DYLD_LIBRARY_PATH
do
   is_defined="true"
   value=$(printenv $v) || is_defined="" || true
   if [ -n "$value" ] || [ -n "$is_defined" ]
   then
       echo export "$v='$value'" >> "$script_folder/deactivate_conanbuildenv-release-x86_64.sh"
   else
       echo unset $v >> "$script_folder/deactivate_conanbuildenv-release-x86_64.sh"
   fi
done

export PATH="/root/.conan2/p/proto2cb26e4f6439f/p/bin:$PATH"
export LD_LIBRARY_PATH="/root/.conan2/p/proto2cb26e4f6439f/p/lib:$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH="/root/.conan2/p/proto2cb26e4f6439f/p/lib:$DYLD_LIBRARY_PATH"