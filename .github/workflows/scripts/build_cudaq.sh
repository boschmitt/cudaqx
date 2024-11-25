#!/bin/sh

# ============================================================================ #
# Copyright (c) 2022 - 2024 NVIDIA Corporation & Affiliates.                   #
# All rights reserved.                                                         #
#                                                                              #
# This source code and the accompanying materials are made available under     #
# the terms of the Apache License 2.0 which accompanies this distribution.     #
# ============================================================================ #


export CUDA_VERSION=12.0

# We need to use a newer toolchain because CUDA-QX libraries rely on c++20
source /opt/rh/gcc-toolset-11/enable

export CC=gcc
export CXX=g++

python_version=3.10
python=python${python_version}
${python} -m pip install --no-cache-dir numpy auditwheel

echo "Building CUDA-Q."
cd cudaq

# ==============================================================================
# Building MLIR bindings
# ==============================================================================

echo "Building MLIR bindings for ${python}" && \
    rm -rf "$LLVM_INSTALL_PREFIX/src" "$LLVM_INSTALL_PREFIX/python_packages" && \
    Python3_EXECUTABLE="$(which ${python})" \
    LLVM_PROJECTS='clang;mlir;python-bindings' \
    LLVM_CMAKE_CACHE=/cmake/caches/LLVM.cmake LLVM_SOURCE=/llvm-project \
    bash /scripts/build_llvm.sh -c Release -v 

# ==============================================================================
# Building CUDA-Q
# ==============================================================================

CUDAQ_PATCH='diff --git a/CMakeLists.txt b/CMakeLists.txt
index 3f2c138..ddb15b3 100644
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -540,7 +540,7 @@ add_subdirectory(tools)
 add_subdirectory(utils)
 
 if (CUDAQ_ENABLE_PYTHON)
-  find_package(Python 3 COMPONENTS Interpreter Development)
+  find_package(Python 3 COMPONENTS Interpreter Development.Module)
   
   # Apply specific patch to pybind11 for our documentation.
   # Only apply the patch if not already applied.
diff --git a/python/runtime/cudaq/domains/plugins/CMakeLists.txt b/python/runtime/cudaq/domains/plugins/CMakeLists.txt
index 7b7541d..2261334 100644
--- a/python/runtime/cudaq/domains/plugins/CMakeLists.txt
+++ b/python/runtime/cudaq/domains/plugins/CMakeLists.txt
@@ -17,6 +17,6 @@ if (SKBUILD)
     if (NOT Python_FOUND)
       message(FATAL_ERROR "find_package(Python) not run?")
     endif()
-    target_link_libraries(cudaq-pyscf PRIVATE Python::Python pybind11::pybind11 cudaq-chemistry cudaq-spin cudaq cudaq-py-utils)
+    target_link_libraries(cudaq-pyscf PRIVATE Python::Module pybind11::pybind11 cudaq-chemistry cudaq-spin cudaq cudaq-py-utils)
 endif()
 install(TARGETS cudaq-pyscf DESTINATION lib/plugins)'

CUDAQ_PATCH2='diff --git a/lib/Frontend/nvqpp/ConvertDecl.cpp b/lib/Frontend/nvqpp/ConvertDecl.cpp
index 149959c8e..ea23990f6 100644
--- a/lib/Frontend/nvqpp/ConvertDecl.cpp
+++ b/lib/Frontend/nvqpp/ConvertDecl.cpp
@@ -169,8 +169,10 @@ bool QuakeBridgeVisitor::interceptRecordDecl(clang::RecordDecl *x) {
       auto fnTy = cast<FunctionType>(popType());
       return pushType(cc::IndirectCallableType::get(fnTy));
     }
-    auto loc = toLocation(x);
-    TODO_loc(loc, "unhandled type, " + name + ", in cudaq namespace");
+    if (!isInNamespace(x, "solvers") && !isInNamespace(x, "qec")) {
+      auto loc = toLocation(x);
+      TODO_loc(loc, "unhandled type, " + name + ", in cudaq namespace");
+    }
   }
   if (isInNamespace(x, "std")) {
     if (name.equals("vector")) {
diff --git a/lib/Frontend/nvqpp/ConvertExpr.cpp b/lib/Frontend/nvqpp/ConvertExpr.cpp
index e6350d1c5..28c98c6cb 100644
--- a/lib/Frontend/nvqpp/ConvertExpr.cpp
+++ b/lib/Frontend/nvqpp/ConvertExpr.cpp
@@ -2050,7 +2050,9 @@ bool QuakeBridgeVisitor::VisitCallExpr(clang::CallExpr *x) {
       return pushValue(call.getResult(0));
     }
 
-    TODO_loc(loc, "unknown function, " + funcName + ", in cudaq namespace");
+    if (!isInNamespace(func, "solvers") && !isInNamespace(func, "qec")) {
+      TODO_loc(loc, "unknown function, " + funcName + ", in cudaq namespace");
+    }
   } // end in cudaq namespace
 
   if (isInNamespace(func, "std")) {'

echo "$CUDAQ_PATCH" | git apply --verbose
echo "$CUDAQ_PATCH2" | git apply --verbose

$python -m venv --system-site-packages .venv
source .venv/bin/activate
CUDAQ_BUILD_TESTS=FALSE bash scripts/build_cudaq.sh -v
