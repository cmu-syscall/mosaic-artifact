#ifndef MOSAIC_CUDA_WRAPPERS_H
#define MOSAIC_CUDA_WRAPPERS_H

#include <cuda_runtime_api.h>
#include <cublas_v2.h>
#include <cusparse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MOSAIC_CUDA_CHECK(call) do { \
  int status = (int)(call); \
  if (status != 0) { \
    fprintf(stderr, "%s failed with status %d\n", #call, status); \
    abort(); \
  } \
} while (0)

static void *mosaic_cuda_alloc(size_t bytes, const void *source) {
  void *device = NULL;
  MOSAIC_CUDA_CHECK(cudaMalloc(&device, bytes ? bytes : 1));
  if (source && bytes)
    MOSAIC_CUDA_CHECK(cudaMemcpy(device, source, bytes, cudaMemcpyHostToDevice));
  return device;
}

static void mosaic_cuda_sgemm(int m, int n, int k, const float *a,
                               const float *b, float *c) {
  float *da = (float *)mosaic_cuda_alloc((size_t)m * k * sizeof(float), a);
  float *db = (float *)mosaic_cuda_alloc((size_t)k * n * sizeof(float), b);
  float *dc = (float *)mosaic_cuda_alloc((size_t)m * n * sizeof(float), NULL);
  cublasHandle_t handle;
  const float alpha = 1, beta = 0;
  MOSAIC_CUDA_CHECK(cublasCreate(&handle));
  MOSAIC_CUDA_CHECK(cublasSetMathMode(handle, CUBLAS_PEDANTIC_MATH));
  // Row-major C = AB is column-major C^T = B^T A^T.
  MOSAIC_CUDA_CHECK(cublasSgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N, n, m, k,
                              &alpha, db, n, da, k, &beta, dc, n));
  MOSAIC_CUDA_CHECK(cudaDeviceSynchronize());
  MOSAIC_CUDA_CHECK(cudaMemcpy(c, dc, (size_t)m * n * sizeof(float), cudaMemcpyDeviceToHost));
  MOSAIC_CUDA_CHECK(cublasDestroy(handle));
  MOSAIC_CUDA_CHECK(cudaFree(dc));
  MOSAIC_CUDA_CHECK(cudaFree(db));
  MOSAIC_CUDA_CHECK(cudaFree(da));
}

static void mosaic_cuda_sgemv(int rows, int columns, const float *a,
                               const float *x, float *y) {
  float *da = (float *)mosaic_cuda_alloc((size_t)rows * columns * sizeof(float), a);
  float *dx = (float *)mosaic_cuda_alloc((size_t)columns * sizeof(float), x);
  float *dy = (float *)mosaic_cuda_alloc((size_t)rows * sizeof(float), NULL);
  cublasHandle_t handle;
  const float alpha = 1, beta = 0;
  MOSAIC_CUDA_CHECK(cublasCreate(&handle));
  MOSAIC_CUDA_CHECK(cublasSetMathMode(handle, CUBLAS_PEDANTIC_MATH));
  MOSAIC_CUDA_CHECK(cublasSgemv(handle, CUBLAS_OP_T, columns, rows,
                              &alpha, da, columns, dx, 1, &beta, dy, 1));
  MOSAIC_CUDA_CHECK(cudaDeviceSynchronize());
  MOSAIC_CUDA_CHECK(cudaMemcpy(y, dy, (size_t)rows * sizeof(float), cudaMemcpyDeviceToHost));
  MOSAIC_CUDA_CHECK(cublasDestroy(handle));
  MOSAIC_CUDA_CHECK(cudaFree(dy));
  MOSAIC_CUDA_CHECK(cudaFree(dx));
  MOSAIC_CUDA_CHECK(cudaFree(da));
}

typedef struct {
  cusparseSpMatDescr_t matrix;
  void *offsets, *columns, *values;
} mosaic_cuda_csr;

static mosaic_cuda_csr mosaic_cuda_upload_csr(const taco_tensor_t *tensor) {
  mosaic_cuda_csr csr;
  const int rows = tensor->dimensions[0];
  const int *offsets = (const int *)tensor->indices[1][0];
  const int nnz = offsets[rows];
  csr.offsets = mosaic_cuda_alloc((size_t)(rows + 1) * sizeof(int), offsets);
  csr.columns = mosaic_cuda_alloc((size_t)nnz * sizeof(int), tensor->indices[1][1]);
  csr.values = mosaic_cuda_alloc((size_t)nnz * sizeof(float), tensor->vals);
  MOSAIC_CUDA_CHECK(cusparseCreateCsr(&csr.matrix, rows, tensor->dimensions[1], nnz,
      csr.offsets, csr.columns, csr.values, CUSPARSE_INDEX_32I, CUSPARSE_INDEX_32I,
      CUSPARSE_INDEX_BASE_ZERO, CUDA_R_32F));
  return csr;
}

static void mosaic_cuda_free_csr(mosaic_cuda_csr csr) {
  MOSAIC_CUDA_CHECK(cusparseDestroySpMat(csr.matrix));
  MOSAIC_CUDA_CHECK(cudaFree(csr.values));
  MOSAIC_CUDA_CHECK(cudaFree(csr.columns));
  MOSAIC_CUDA_CHECK(cudaFree(csr.offsets));
}

static void cuda_spmv(taco_tensor_t *a, const float *x, float *y, int rows) {
  if (((const int *)a->indices[1][0])[rows] == 0) {
    memset(y, 0, (size_t)rows * sizeof(float));
    return;
  }
  cusparseHandle_t handle;
  cusparseDnVecDescr_t vx, vy;
  const float alpha = 1, beta = 0;
  size_t bytes = 0;
  MOSAIC_CUDA_CHECK(cusparseCreate(&handle));
  mosaic_cuda_csr csr = mosaic_cuda_upload_csr(a);
  float *dx = (float *)mosaic_cuda_alloc((size_t)a->dimensions[1] * sizeof(float), x);
  float *dy = (float *)mosaic_cuda_alloc((size_t)rows * sizeof(float), NULL);
  MOSAIC_CUDA_CHECK(cusparseCreateDnVec(&vx, a->dimensions[1], dx, CUDA_R_32F));
  MOSAIC_CUDA_CHECK(cusparseCreateDnVec(&vy, rows, dy, CUDA_R_32F));
  MOSAIC_CUDA_CHECK(cusparseSpMV_bufferSize(handle, CUSPARSE_OPERATION_NON_TRANSPOSE,
      &alpha, csr.matrix, vx, &beta, vy, CUDA_R_32F, CUSPARSE_SPMV_ALG_DEFAULT, &bytes));
  void *buffer = mosaic_cuda_alloc(bytes, NULL);
  MOSAIC_CUDA_CHECK(cusparseSpMV(handle, CUSPARSE_OPERATION_NON_TRANSPOSE,
      &alpha, csr.matrix, vx, &beta, vy, CUDA_R_32F, CUSPARSE_SPMV_ALG_DEFAULT, buffer));
  MOSAIC_CUDA_CHECK(cudaDeviceSynchronize());
  MOSAIC_CUDA_CHECK(cudaMemcpy(y, dy, (size_t)rows * sizeof(float), cudaMemcpyDeviceToHost));
  MOSAIC_CUDA_CHECK(cudaFree(buffer));
  MOSAIC_CUDA_CHECK(cusparseDestroyDnVec(vy));
  MOSAIC_CUDA_CHECK(cusparseDestroyDnVec(vx));
  MOSAIC_CUDA_CHECK(cudaFree(dy));
  MOSAIC_CUDA_CHECK(cudaFree(dx));
  mosaic_cuda_free_csr(csr);
  MOSAIC_CUDA_CHECK(cusparseDestroy(handle));
}

static void mosaic_cuda_spmm(taco_tensor_t *a, int columns, const float *b, float *c) {
  const int rows = a->dimensions[0], inner = a->dimensions[1];
  const size_t output_bytes = (size_t)rows * columns * sizeof(float);
  if (((const int *)a->indices[1][0])[rows] == 0) {
    memset(c, 0, output_bytes);
    return;
  }
  cusparseHandle_t handle;
  cusparseDnMatDescr_t mb, mc;
  const float alpha = 1, beta = 0;
  size_t bytes = 0;
  MOSAIC_CUDA_CHECK(cusparseCreate(&handle));
  mosaic_cuda_csr csr = mosaic_cuda_upload_csr(a);
  float *db = (float *)mosaic_cuda_alloc((size_t)inner * columns * sizeof(float), b);
  float *dc = (float *)mosaic_cuda_alloc(output_bytes, NULL);
  MOSAIC_CUDA_CHECK(cusparseCreateDnMat(&mb, inner, columns, columns, db, CUDA_R_32F, CUSPARSE_ORDER_ROW));
  MOSAIC_CUDA_CHECK(cusparseCreateDnMat(&mc, rows, columns, columns, dc, CUDA_R_32F, CUSPARSE_ORDER_ROW));
  MOSAIC_CUDA_CHECK(cusparseSpMM_bufferSize(handle, CUSPARSE_OPERATION_NON_TRANSPOSE,
      CUSPARSE_OPERATION_NON_TRANSPOSE, &alpha, csr.matrix, mb, &beta, mc,
      CUDA_R_32F, CUSPARSE_SPMM_ALG_DEFAULT, &bytes));
  void *buffer = mosaic_cuda_alloc(bytes, NULL);
  MOSAIC_CUDA_CHECK(cusparseSpMM(handle, CUSPARSE_OPERATION_NON_TRANSPOSE,
      CUSPARSE_OPERATION_NON_TRANSPOSE, &alpha, csr.matrix, mb, &beta, mc,
      CUDA_R_32F, CUSPARSE_SPMM_ALG_DEFAULT, buffer));
  MOSAIC_CUDA_CHECK(cudaDeviceSynchronize());
  MOSAIC_CUDA_CHECK(cudaMemcpy(c, dc, output_bytes, cudaMemcpyDeviceToHost));
  MOSAIC_CUDA_CHECK(cudaFree(buffer));
  MOSAIC_CUDA_CHECK(cusparseDestroyDnMat(mc));
  MOSAIC_CUDA_CHECK(cusparseDestroyDnMat(mb));
  MOSAIC_CUDA_CHECK(cudaFree(dc));
  MOSAIC_CUDA_CHECK(cudaFree(db));
  mosaic_cuda_free_csr(csr);
  MOSAIC_CUDA_CHECK(cusparseDestroy(handle));
}


#undef MOSAIC_CUDA_CHECK
#endif
