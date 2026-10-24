#ifndef SCHEDULING_ENGINE_H
#define SCHEDULING_ENGINE_H
// UTF-8 JSON in; owned UTF-8 JSON out. Free each result exactly once.
char *scheduling_engine_request(const char *request);
char *anki_backend_request(const char *request);
void scheduling_engine_free(char *result);
#endif
