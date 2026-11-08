#ifndef GSL_WRAPPERS_H
#define GSL_WRAPPERS_H
#include <gsl/gsl_blas.h>
#include <stdio.h>

void set_gsl_float_data(gsl_vector_float * vec, float * data){
    vec->data = data;
 }
  void set_gsl_mat_data_row_major_s(gsl_matrix_float * mat, float * data){
    mat->data = data;
 }
  void print_array(float * vals, int num_elem){
     for (int i = 0; i < num_elem; i++){
       printf("elem[%d]=%f\\n", i, vals[i]);
     }
     printf("next\\n");
 }
#endif
