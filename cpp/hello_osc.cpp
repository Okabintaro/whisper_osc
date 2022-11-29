#include "tinyosc.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
  printf("Hello OSC!\n");

  // declare a buffer for writing the OSC packet into
  char buffer[1024];
  int sockfd;
  struct sockaddr_in addr;

  if ((sockfd = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
    perror("Failure creating socket");
    return -1;
  }
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons(9000);
  addr.sin_addr.s_addr = INADDR_ANY;

  // write the OSC packet to the buffer
  // returns the number of bytes written to the buffer, negative on error
  // note that tosc_write will clear the entire buffer before writing to it
  int len = tosc_writeMessage(buffer, sizeof(buffer),
                              "/chatbox/input", // the address
                              "sT",             // the format; 'f':32-bit float,
                                    // 's':ascii string, 'i':32-bit integer
                              "Hello VRChat!", true);

  // send the data out of the socket
  // send(socket_fd, buffer, len, 0);
  sendto(sockfd, (const char *)buffer, len, MSG_CONFIRM,
         (struct sockaddr *)&addr, sizeof(addr));
  close(sockfd);

  return 0;
}
