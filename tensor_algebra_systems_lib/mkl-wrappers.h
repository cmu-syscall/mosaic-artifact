#ifndef MKL_WRAPPERS_H
#define MKL_WRAPPERS_H

#include "mkl.h"

void sgemm_mkl_internal(int dim, float * A_vals, float * b_vals, float * d_vals){

    MKL_INT dimA = dim;
    float alpha = 1;
    float beta = 0;

    sgemm("n", "n", &dimA, &dimA, &dimA, &alpha, A_vals, &dimA, b_vals, &dimA, &beta, d_vals, &dimA);
}

void ssymv_mkl_internal(int dim, float * A_vals, float * b_vals, float * d_vals){

    MKL_INT dimA = dim;
    MKL_INT inc = 1;
    float alpha = 1;
    float beta = 0;

    ssymv("u", &dimA, &alpha, A_vals, &dimA, b_vals, &inc, &beta, d_vals, &inc);
}

float sdot_mkl_internal(int dim, float * A_vals, float * b_vals){

    MKL_INT dimA = dim;
    MKL_INT inc = 1;

    return sdot(&dimA, A_vals, &inc, b_vals, &inc);
}


void mkl_sparse_s_add_internal(int m, taco_tensor_t * A, taco_tensor_t * B, taco_tensor_t * C){

  sparse_matrix_t A_csr;
  int*  A_pos = (int*)(A->indices[1][0]);
  mkl_sparse_s_create_csr(&A_csr, SPARSE_INDEX_BASE_ZERO, m, m, A_pos, A_pos+1, (int*)A->indices[1][1], (float*)A->vals);

  sparse_matrix_t B_csr;
  int*  B_pos = (int*)(B->indices[1][0]);
  mkl_sparse_s_create_csr(&B_csr, SPARSE_INDEX_BASE_ZERO, m, m, B_pos, B_pos+1, (int*)B->indices[1][1], (float*)B->vals);

 struct matrix_descr desc;
  desc.type = SPARSE_MATRIX_TYPE_GENERAL;

 sparse_matrix_t * C_csr;
  mkl_sparse_s_add(SPARSE_OPERATION_NON_TRANSPOSE, A_csr, (float) 1, B_csr, C_csr);
}

taco_tensor_t * convert_coo_to_csr(taco_tensor_t *COO) {
    taco_mode_t mode_types[] = {taco_mode_dense, taco_mode_sparse};
    taco_tensor_t *CSR = init_taco_tensor_t(COO->order, COO->csize, 
    COO->dimensions, COO->mode_ordering, mode_types);

    int*  COO_pos = (int*)(COO->indices[0][0]);
    int32_t start = COO_pos[0];
    int32_t end = COO_pos[1];

    int CSR_dimension = (int)(COO->dimensions[0]);
    CSR->indices[1][0] = malloc(sizeof(int) * (COO->dimensions[0] + 1));
    CSR->indices[1][1] = COO->indices[1][1];
    CSR->vals = COO->vals;
    int* CSR_pos = (int*)CSR->indices[1][0];

    for (int i = 0; i < CSR_dimension + 1; i++){
        CSR_pos[i] = 0;
    }

    int*  COO1_crd = (int*)(COO->indices[0][1]);
    int*  COO2_crd = (int*)(COO->indices[1][1]);

    while (start < end) {
        CSR_pos[COO1_crd[start] + 1]++;
        start++;
    }

    for (int i = 0; i < CSR_dimension; i++){
        CSR_pos[i+1] += CSR_pos[i];
    }

    return CSR;
}

void mkl_sparse_s_mm_internal(int m, taco_tensor_t * A, taco_tensor_t * b, float * c)
{
    sparse_matrix_t A_csr;
    struct matrix_descr desc = {0};
    desc.type = SPARSE_MATRIX_TYPE_GENERAL;
    int *A_pos = (int *)A->indices[1][0];
    const int columns = b->dimensions[1];
    if (A_pos[m] == 0) {
        for (size_t index = 0; index < (size_t)m * columns; ++index) c[index] = 0;
        return;
    }
    sparse_status_t status = mkl_sparse_s_create_csr(&A_csr, SPARSE_INDEX_BASE_ZERO,
        m, A->dimensions[1], A_pos, A_pos + 1, (int *)A->indices[1][1], (float *)A->vals);
    if (status != SPARSE_STATUS_SUCCESS) abort();
    status = mkl_sparse_s_mm(SPARSE_OPERATION_NON_TRANSPOSE, 1, A_csr, desc,
        SPARSE_LAYOUT_ROW_MAJOR, (float *)b->vals, columns, columns, 0, c, columns);
    mkl_sparse_destroy(A_csr);
    if (status != SPARSE_STATUS_SUCCESS) abort();
}

void wrapper_convert(int m, taco_tensor_t * A, taco_tensor_t * B, float * C){
    taco_tensor_t *CSR_A = convert_coo_to_csr(A);
     printf("out1\n");
    mkl_sparse_s_mm_internal(m, CSR_A, B, C);
    printf("out\n");
    free(CSR_A->indices[1][0]);
}

#endif
