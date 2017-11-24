#include "traildb.h"

tdb_item* tdb_event_item_pointer(tdb_event* e) {
    return &(e->items);
};
