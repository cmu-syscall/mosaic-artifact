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

#ifdef __cplusplus
#include <stdexcept>

namespace mosaic_cuda {
namespace detail {

inline void check(cudaError_t status) {
  if (status != cudaSuccess) {
    throw std::runtime_error(cudaGetErrorString(status));
  }
}

inline void check(cusparseStatus_t status) {
  if (status != CUSPARSE_STATUS_SUCCESS) {
    throw std::runtime_error(cusparseGetErrorString(status));
  }
}

struct DeviceBuffer {
  DeviceBuffer() = default;
  DeviceBuffer(const DeviceBuffer&) = delete;
  DeviceBuffer& operator=(const DeviceBuffer&) = delete;

  void* data = nullptr;
  ~DeviceBuffer() {
    if (data) cudaFree(data);
  }

  void allocate(size_t bytes) {
    if (bytes != 0) {
      check(cudaMalloc(&data, bytes));
    }
  }

  void upload(const void* host, size_t bytes) {
    allocate(bytes);
    check(cudaMemcpy(data, host, bytes, cudaMemcpyHostToDevice));
  }
};

} // namespace detail

// Prepared FP32 SDDMM for a nonempty, zero-based CSR pattern, with row-major left and
// column-major right operands. Download returns values in CSR storage order.
class Sddmm {
public:
  Sddmm(const taco_tensor_t& pattern, int inner, const float* left,
        const float* right) : Sddmm() {
    const int rows = pattern.dimensions[0];
    const int cols = pattern.dimensions[1];
    const auto* offsets = reinterpret_cast<const int32_t*>(pattern.indices[1][0]);
    const int nnz = offsets[rows];
    resultBytes = size_t(nnz) * sizeof(float);

    deviceOffsets.upload(offsets, (size_t(rows) + 1) * sizeof(*offsets));
    deviceColumns.upload(pattern.indices[1][1], size_t(nnz) * sizeof(int32_t));
    leftValues.upload(left, size_t(rows) * inner * sizeof(float));
    rightValues.upload(right, size_t(cols) * inner * sizeof(float));
    resultValues.allocate(resultBytes);
    detail::check(cudaMemset(resultValues.data, 0, resultBytes));

    detail::check(cusparseCreate(&handle));
    detail::check(cusparseCreateDnMat(&leftMatrix, rows, inner, inner, leftValues.data,
                                       CUDA_R_32F, CUSPARSE_ORDER_ROW));
    detail::check(cusparseCreateDnMat(&rightMatrix, inner, cols, inner, rightValues.data,
                                       CUDA_R_32F, CUSPARSE_ORDER_COL));
    detail::check(cusparseCreateCsr(&resultMatrix, rows, cols, nnz, deviceOffsets.data,
        deviceColumns.data, resultValues.data, CUSPARSE_INDEX_32I, CUSPARSE_INDEX_32I,
        CUSPARSE_INDEX_BASE_ZERO, CUDA_R_32F));

    size_t bytes = 0;
    detail::check(cusparseSDDMM_bufferSize(handle, op, op, &alpha, leftMatrix, rightMatrix,
        &beta, resultMatrix, CUDA_R_32F, alg, &bytes));
    workspace.allocate(bytes);
    detail::check(cusparseSDDMM_preprocess(handle, op, op, &alpha, leftMatrix, rightMatrix,
        &beta, resultMatrix, CUDA_R_32F, alg, workspace.data));
    detail::check(cudaDeviceSynchronize());
  }

  ~Sddmm() {
    if (resultMatrix) cusparseDestroySpMat(resultMatrix);
    if (rightMatrix) cusparseDestroyDnMat(rightMatrix);
    if (leftMatrix) cusparseDestroyDnMat(leftMatrix);
    if (handle) cusparseDestroy(handle);
  }

  void run() {
    detail::check(cusparseSDDMM(handle, op, op, &alpha, leftMatrix, rightMatrix,
        &beta, resultMatrix, CUDA_R_32F, alg, workspace.data));
    detail::check(cudaDeviceSynchronize());
  }

  void download(float* output) const {
    detail::check(cudaMemcpy(output, resultValues.data, resultBytes, cudaMemcpyDeviceToHost));
  }

private:
  Sddmm() = default;

  const cusparseOperation_t op = CUSPARSE_OPERATION_NON_TRANSPOSE;
  const cusparseSDDMMAlg_t alg = CUSPARSE_SDDMM_ALG_DEFAULT;
  const float alpha = 1.0f, beta = 0.0f;
  size_t resultBytes = 0;
  cusparseHandle_t handle = nullptr;
  cusparseDnMatDescr_t leftMatrix = nullptr, rightMatrix = nullptr;
  cusparseSpMatDescr_t resultMatrix = nullptr;
  detail::DeviceBuffer deviceOffsets, deviceColumns, leftValues, rightValues, resultValues, workspace;
};

} // namespace mosaic_cuda
#endif

#endif
