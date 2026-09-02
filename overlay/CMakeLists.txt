cmake_minimum_required(VERSION 3.20)
project(armada-control-overlay LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core DBus Gui Widgets Network)
find_package(PkgConfig REQUIRED)
pkg_check_modules(XCB REQUIRED IMPORTED_TARGET xcb)

add_executable(armada-control-overlay main.cpp)
target_link_libraries(armada-control-overlay PRIVATE Qt6::Core Qt6::DBus Qt6::Gui Qt6::Widgets Qt6::Network PkgConfig::XCB)
install(TARGETS armada-control-overlay RUNTIME DESTINATION bin)
