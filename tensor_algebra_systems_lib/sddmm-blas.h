#ifndef MOSAIC_SDDMM_BLAS_H
#define MOSAIC_SDDMM_BLAS_H

#include <string.h>
#include "taco/taco_tensor_t.h"

// The caller supplies row-major left and transposed-right operands and a dense
// output. Clear each row so coordinates absent from the CSR mask stay zero.
static inline void mosaic_sddmm_sdot(const taco_tensor_t* mask, int inner,
                                     const float* left, const float* right_t,
                                     float* output) {
    const int rows = mask->dimensions[0];
    const int cols = mask->dimensions[1];
    const int32_t* offsets = (const int32_t*)mask->indices[1][0];
    const int32_t* columns = (const int32_t*)mask->indices[1][1];
    const float* weights = (const float*)mask->vals;
    for (int row = 0; row < rows; ++row) {
        float* out = output + (size_t)row * cols;
        memset(out, 0, (size_t)cols * sizeof(*out));
        for (int p = offsets[row]; p < offsets[row + 1]; ++p) {
            const int col = columns[p];
            out[col] = weights[p] * cblas_sdot(inner, left + (size_t)row * inner, 1,
                                               right_t + (size_t)col * inner, 1);
        }
    }
}

#endif
