#ifndef MOSAIC_CUDA_WRAPPERS_H
#define MOSAIC_CUDA_WRAPPERS_H

#include <cuda_runtime_api.h>
#include <cusparse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "taco/taco_tensor_t.h"

#define MOSAIC_CUDA_CHECK(call) do {                                      \
    cudaError_t status = (call);                                         \
    if (status != cudaSuccess) {                                         \
        fprintf(stderr, "cuda_spmv: %s: %s\n", #call,                    \
                cudaGetErrorString(status));                             \
        abort();                                                         \
    }                                                                    \
} while (0)

#define MOSAIC_CUSPARSE_CHECK(call) do {                                  \
    cusparseStatus_t status = (call);                                     \
    if (status != CUSPARSE_STATUS_SUCCESS) {                              \
        fprintf(stderr, "cuda_spmv: %s: %s\n", #call,                    \
                cusparseGetErrorString(status));                         \
        abort();                                                         \
    }                                                                    \
} while (0)

// Mosaic supplies host buffers containing zero-based CSR and dense FP32 data.
static inline void cuda_spmv(const taco_tensor_t *matrix, const float *input,
                             float *output, int32_t rows) {
    if (rows == 0) {
        return;
    }

    const int32_t cols = matrix->dimensions[1];
    const int32_t *row_offsets = (const int32_t *)matrix->indices[1][0];
    const int32_t nnz = row_offsets[rows];
    const size_t output_bytes = (size_t)rows * sizeof(float);
    if (nnz == 0) {
        memset(output, 0, output_bytes);
        return;
    }

    const size_t row_bytes = ((size_t)rows + 1) * sizeof(int32_t);
    const size_t index_bytes = (size_t)nnz * sizeof(int32_t);
    const size_t value_bytes = (size_t)nnz * sizeof(float);
    const size_t input_bytes = (size_t)cols * sizeof(float);
    void *device_rows, *device_indices, *device_values, *device_input, *device_output;

    MOSAIC_CUDA_CHECK(cudaMalloc(&device_rows, row_bytes));
    MOSAIC_CUDA_CHECK(cudaMalloc(&device_indices, index_bytes));
    MOSAIC_CUDA_CHECK(cudaMalloc(&device_values, value_bytes));
    MOSAIC_CUDA_CHECK(cudaMalloc(&device_input, input_bytes));
    MOSAIC_CUDA_CHECK(cudaMalloc(&device_output, output_bytes));
    MOSAIC_CUDA_CHECK(cudaMemcpy(device_rows, row_offsets, row_bytes, cudaMemcpyHostToDevice));
    MOSAIC_CUDA_CHECK(cudaMemcpy(device_indices, matrix->indices[1][1], index_bytes,
                                 cudaMemcpyHostToDevice));
    MOSAIC_CUDA_CHECK(cudaMemcpy(device_values, matrix->vals, value_bytes, cudaMemcpyHostToDevice));
    MOSAIC_CUDA_CHECK(cudaMemcpy(device_input, input, input_bytes, cudaMemcpyHostToDevice));

    cusparseHandle_t handle;
    cusparseSpMatDescr_t csr;
    cusparseDnVecDescr_t x, y;
    MOSAIC_CUSPARSE_CHECK(cusparseCreate(&handle));
    MOSAIC_CUSPARSE_CHECK(cusparseCreateCsr(&csr, rows, cols, nnz,
        device_rows, device_indices, device_values, CUSPARSE_INDEX_32I,
        CUSPARSE_INDEX_32I, CUSPARSE_INDEX_BASE_ZERO, CUDA_R_32F));
    MOSAIC_CUSPARSE_CHECK(cusparseCreateDnVec(&x, cols, device_input, CUDA_R_32F));
    MOSAIC_CUSPARSE_CHECK(cusparseCreateDnVec(&y, rows, device_output, CUDA_R_32F));

    const float alpha = 1.0f, beta = 0.0f;
    size_t workspace_bytes;
    void *workspace = NULL;
    MOSAIC_CUSPARSE_CHECK(cusparseSpMV_bufferSize(handle, CUSPARSE_OPERATION_NON_TRANSPOSE,
        &alpha, csr, x, &beta, y, CUDA_R_32F, CUSPARSE_SPMV_ALG_DEFAULT, &workspace_bytes));
    if (workspace_bytes != 0) {
        MOSAIC_CUDA_CHECK(cudaMalloc(&workspace, workspace_bytes));
    }
    MOSAIC_CUSPARSE_CHECK(cusparseSpMV(handle, CUSPARSE_OPERATION_NON_TRANSPOSE,
        &alpha, csr, x, &beta, y, CUDA_R_32F, CUSPARSE_SPMV_ALG_DEFAULT, workspace));
    MOSAIC_CUDA_CHECK(cudaMemcpy(output, device_output, output_bytes, cudaMemcpyDeviceToHost));

    MOSAIC_CUSPARSE_CHECK(cusparseDestroyDnVec(y));
    MOSAIC_CUSPARSE_CHECK(cusparseDestroyDnVec(x));
    MOSAIC_CUSPARSE_CHECK(cusparseDestroySpMat(csr));
    MOSAIC_CUSPARSE_CHECK(cusparseDestroy(handle));
    MOSAIC_CUDA_CHECK(cudaFree(workspace));
    MOSAIC_CUDA_CHECK(cudaFree(device_output));
    MOSAIC_CUDA_CHECK(cudaFree(device_input));
    MOSAIC_CUDA_CHECK(cudaFree(device_values));
    MOSAIC_CUDA_CHECK(cudaFree(device_indices));
    MOSAIC_CUDA_CHECK(cudaFree(device_rows));
}

#undef MOSAIC_CUDA_CHECK
#undef MOSAIC_CUSPARSE_CHECK
#endif
