export MACOSX_DEPLOYMENT_TARGET=10.14
cmake -S . -B Build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=1
cd Build
make -j10