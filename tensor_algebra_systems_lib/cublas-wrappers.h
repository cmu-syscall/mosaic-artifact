#ifndef MOSAIC_CUBLAS_WRAPPERS_H
#define MOSAIC_CUBLAS_WRAPPERS_H

#include <cublas_v2.h>
#include <cuda_runtime_api.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* Check each call once and report its source location on failure. */
#ifndef CUDA_CHECK
#define CUDA_CHECK(call) do { \
    cudaError_t mosaic_cuda_status = (call); \
    if (mosaic_cuda_status != cudaSuccess) { \
        fprintf(stderr, "CUDA error at %s:%d: %s\n", __FILE__, __LINE__, \
                cudaGetErrorString(mosaic_cuda_status)); \
        abort(); \
    } \
} while (0)
#endif

#ifndef CUBLAS_CHECK
#define CUBLAS_CHECK(call) do { \
    cublasStatus_t mosaic_cublas_status = (call); \
    if (mosaic_cublas_status != CUBLAS_STATUS_SUCCESS) { \
        fprintf(stderr, "cuBLAS error at %s:%d: %d\n", __FILE__, __LINE__, \
                (int)mosaic_cublas_status); \
        abort(); \
    } \
} while (0)
#endif

/* Compute y = A*x for a dim-by-dim row-major matrix and contiguous vectors.
 * All pointers refer to host memory. The result is ready on return. Each call
 * includes allocation, transfers, and handle creation in its execution time.
 * Include this header from C or C++ and link with -lcublas -lcudart.
 * This void interface reports CUDA/cuBLAS and invalid-input failures by aborting.
 */
static inline void sgemv_cublas_internal(int dim, float *A, float *x, float *y) {
    size_t n, matrix_bytes, vector_bytes;
    float *device_A = NULL, *device_x = NULL, *device_y = NULL;
    cublasHandle_t handle;
    const float alpha = 1.0f, beta = 0.0f;

    if (dim < 0) {
        fprintf(stderr, "sgemv_cublas_internal: negative dimension\n");
        abort();
    }
    if (dim == 0) {
        return;
    }
    n = (size_t)dim;
    if (A == NULL || x == NULL || y == NULL ||
        n > SIZE_MAX / sizeof(float) / n) {
        fprintf(stderr, "sgemv_cublas_internal: invalid buffers or matrix size\n");
        abort();
    }
    matrix_bytes = n * n * sizeof(float);
    vector_bytes = n * sizeof(float);

    CUBLAS_CHECK(cublasCreate(&handle));
    CUDA_CHECK(cudaMalloc((void **)&device_A, matrix_bytes));
    CUDA_CHECK(cudaMalloc((void **)&device_x, vector_bytes));
    CUDA_CHECK(cudaMalloc((void **)&device_y, vector_bytes));
    CUDA_CHECK(cudaMemcpy(device_A, A, matrix_bytes,
                                       cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(device_x, x, vector_bytes,
                                       cudaMemcpyHostToDevice));

    /* cuBLAS sees the row-major buffer as column-major A^T. Transpose it
     * back to compute A*x. A new handle uses host pointer mode for scalars.
     * beta=0 means device_y does not need an initial value.
     */
    CUBLAS_CHECK(cublasSgemv(handle, CUBLAS_OP_T, dim, dim, &alpha,
                                   device_A, dim, device_x, 1, &beta,
                                   device_y, 1));
    CUDA_CHECK(cudaMemcpy(y, device_y, vector_bytes,
                                       cudaMemcpyDeviceToHost));

    CUDA_CHECK(cudaFree(device_y));
    CUDA_CHECK(cudaFree(device_x));
    CUDA_CHECK(cudaFree(device_A));
    CUBLAS_CHECK(cublasDestroy(handle));
}

#endif /* MOSAIC_CUBLAS_WRAPPERS_H */
