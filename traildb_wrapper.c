#include "traildb.h"

uint64_t* tdb_event_item_pointer(tdb_event* e) {
    return &(e->items);
};
