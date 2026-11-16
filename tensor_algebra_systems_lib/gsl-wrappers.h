void set_gsl_float_data(gsl_vector_float * vec, float * data){ 
    vec->data = data;
 } 
  void free_tblis_tensor(tblis_tensor * t){ 
    free(t->len);
    free(t->stride);
 } 
  void set_gsl_mat_data_row_major_s(gsl_matrix_float * mat, float * data){
    mat->data = data;
 } 
  void set_tensor_data_s(tensor_float * t, float * data){ 
    t->data = data;
 } 
  void print_array(float * vals, int num_elem){ 
     for (int i = 0; i < num_elem; i++){ 
       printf("elem[%d]=%f\\n", i, vals[i]); 
     } 
     printf("next\\n"); 
 } 
