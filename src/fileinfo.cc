#include <cassert>
#include <cstdint>
#include <filesystem>
#include <iostream>

namespace fs = std::filesystem;

extern "C" bool isDirRaw(const char* path, bool* result) {
    assert(path != nullptr && result != nullptr);
    std::error_code errcode;

#ifdef ZIG_DEBUG_MODE
    std::cout << "path: " << path << '\n';
#endif

    if (fs::symlink_status(path, errcode).type() == fs::file_type::symlink) {
        *result = false;
        if (errcode) {
            std::cerr << "error (fileinfo.cc): " << errcode.message() << '\n';
            return false;
        }
        return true;
    }

#ifdef ZIG_DEBUG_MODE
    std::cout << "reached here\n";
#endif

    *result = fs::symlink_status(path, errcode).type() == fs::file_type::directory;
    if (errcode) {
        std::cerr << "error (fileinfo.cc): " << errcode.message() << '\n';
        return false;
    }

    return true;
}

extern "C" bool fileSizeRaw(const char* path, uintmax_t* result) {
    assert(path != nullptr && result != nullptr);
    std::error_code errcode;

#ifdef ZIG_DEBUG_MODE
    std::cout << "path: " << path << '\n';
#endif

    *result = fs::file_size(path, errcode);

    if (errcode) {
        std::cerr << "ERROR (fileinfo.cc): " << errcode.message() << '\n';
        return false;
    }

    return true;
}
