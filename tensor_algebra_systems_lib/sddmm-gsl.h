#ifndef MOSAIC_SDDMM_GSL_H
#define MOSAIC_SDDMM_GSL_H

#include <gsl/gsl_blas.h>
#include <string.h>
#include "taco/taco_tensor_t.h"

// Both inputs store the reduction dimension contiguously. GSL views borrow
// those rows, so sampling an entry requires no packing or allocation.
static inline void mosaic_gsl_sampled_dot(const taco_tensor_t* mask, int inner,
                                          const float* left, const float* right_t,
                                          float* output, const float* weights, int dense_output) {
    const int rows = mask->dimensions[0];
    const int cols = mask->dimensions[1];
    const int32_t* offsets = (const int32_t*)mask->indices[1][0];
    const int32_t* columns = (const int32_t*)mask->indices[1][1];
    if (dense_output) {
        memset(output, 0, (size_t)rows * cols * sizeof(*output));
    }
    for (int row = 0; row < rows; ++row) {
        if (offsets[row] == offsets[row + 1]) continue;
        gsl_vector_float_const_view lhs =
            gsl_vector_float_const_view_array(left + (size_t)row * inner, inner);
        for (int p = offsets[row]; p < offsets[row + 1]; ++p) {
            const int col = columns[p];
            gsl_vector_float_const_view rhs =
                gsl_vector_float_const_view_array(right_t + (size_t)col * inner, inner);
            float dot;
            gsl_blas_sdot(&lhs.vector, &rhs.vector, &dot);
            const size_t index = dense_output ? (size_t)row * cols + col : (size_t)p;
            output[index] = weights ? weights[p] * dot : dot;
        }
    }
}

static inline void mosaic_gsl_sddmm_dense(const taco_tensor_t* mask, int inner,
                                          const float* left, const float* right_t,
                                          float* output) {
    mosaic_gsl_sampled_dot(mask, inner, left, right_t, output, (const float*)mask->vals, 1);
}

// Output must be preassembled with the mask's CSR pattern.
static inline void mosaic_gsl_sddmm_csr(const taco_tensor_t* mask, int inner,
                                        const float* left, const float* right_t, float* output) {
    mosaic_gsl_sampled_dot(mask, inner, left, right_t, output, (const float*)mask->vals, 0);
}

#endif
