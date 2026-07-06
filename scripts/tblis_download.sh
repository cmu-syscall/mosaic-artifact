#!/bin/bash
# Step 0: Create a tblis directory where the lib will be stored.
cd $TENSOR_ALGEBRA_LIB
mkdir tblis

# Step 1: remove the tblis directory if it exists directly
cd $TENSOR_ALGEBRA_SRC
rm -rf tblis

# Step 1: Download
git clone https://github.com/devinamatthews/tblis.git

# Step 2: Build library from source and put lib + headers to in the
# TENSOR_ALGEBRA_LIB/tblis dir.

cd tblis
git checkout d5c9100565afa215ad28c02e2b07860d3698cb3a
./configure --prefix=$TENSOR_ALGEBRA_LIB/tblis && make && make install

