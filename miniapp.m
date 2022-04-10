#import  <UIKit/UIKit.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
typedef int mysocket;

static void cancelSourceAndSock(__strong dispatch_source_t* sourcePtr, mysocket* sockPtr)
{
  if (*sourcePtr!=NULL) {
    dispatch_source_cancel(*sourcePtr);
    *sourcePtr=NULL;
  }
  if (*sockPtr!=0) {
    close(*sockPtr);
    *sockPtr=0;
  }
}

static dispatch_source_t createSockSource(int sock, dispatch_source_type_t type, dispatch_block_t block)
{
  dispatch_source_t source = dispatch_source_create(type, sock, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(source, block);
  return source;
}

#define SOCKERR(cond,doExit) \
if((cond)){ \
  NSLog(@"%s syserr=%d %s\n",#cond,errno,strerror(errno)); \
  if (doExit) {exit(1);} \
}

static mysocket createTCPServerSocket(int portnum, int* actualport)
{
  mysocket servsock;
  struct sockaddr_in servaddr;
  int gotport;
  socklen_t len = sizeof ( servaddr );
again:
  SOCKERR( ( servsock = socket( AF_INET, SOCK_STREAM, 0 ) ) < 0, TRUE );
  memset( &servaddr, 0, sizeof ( servaddr ) );
  servaddr.sin_family = AF_INET;
#if TARGET_IPHONE_SIMULATOR
  //prevent firewall popup
  servaddr.sin_addr.s_addr = htonl( INADDR_LOOPBACK );
#else
  servaddr.sin_addr.s_addr = htonl( INADDR_ANY );
#endif
  servaddr.sin_port = htons((u_short)portnum );
  if ( bind( servsock, (const struct sockaddr*) &servaddr, sizeof ( servaddr ) ) < 0) {
    close(servsock);
    portnum++;
    NSLog(@"increase port to :%d\n",portnum);
    goto again;
  }
  SOCKERR( getsockname( servsock, (struct sockaddr*) &servaddr, &len ) < 0, TRUE );
  gotport = ntohs( servaddr.sin_port );
  if (actualport!=NULL) {
    *actualport = gotport;
  }
  SOCKERR( listen( servsock, 1024 ) < 0, TRUE );
  NSLog(@"did create bound socket at port:%d\n", gotport );
  return servsock;
}

@interface MyConnection: NSObject
{
  mysocket _sock;
  NSMutableString* _buf;
  dispatch_source_t _source;
}
@property (readonly) mysocket sock;
@property (atomic) dispatch_source_t source;
@end
@implementation MyConnection
-(id)initWithSock:(mysocket)sock
{
  self=[super init];
  if (self!=nil) {
    _sock=sock;
    _buf=[NSMutableString string];
  }
  return self;
}

-(void)cancel
{
  cancelSourceAndSock(&_source, &_sock);
}

-(void)dealloc
{
  [self cancel];
}

-(void)addToBuf:(const char*) buf size:(int)size
{
  NSString* str=[[NSString alloc] initWithBytes:buf length:(NSUInteger)size encoding:NSUTF8StringEncoding];
  [_buf appendString:str];
  if ([_buf hasSuffix:@"\n"]) {
    NSLog(@"did receive:%@",_buf);
    //...and echo it back
    NSData* data=[_buf dataUsingEncoding:NSUTF8StringEncoding];
    send(_sock, data.bytes, data.length, 0);
    _buf=[NSMutableString string];
  }
}
@end

@interface MyTCPServer: NSObject
{
  NSMutableArray* _connections;
  mysocket _servsock;
  dispatch_source_t _servsource;
}
@end
@implementation MyTCPServer
-(id)init
{
  self=[super init];
  if (self!=nil) {
    _connections=[NSMutableArray array];
  }
  return self;
}

-(void)removeConn:(MyConnection*)conn
{
  [conn cancel];
  NSUInteger idx=[_connections indexOfObject:conn];
  assert(idx!=NSNotFound);
  NSLog(@"remove connection at:%ld",(long)idx);
  [_connections removeObjectAtIndex:idx];
}

-(void)receive:(MyConnection*)conn
{
  char buf[1024];
  int len = (int) recv( conn.sock, buf, sizeof(buf), 0 );
  if (len<=0) {
    [self removeConn:conn];
  } else {
    [conn addToBuf:buf size:len];
  }
}

-(void) newConnection:(mysocket)sock
{
  MyConnection* conn=[[MyConnection alloc] initWithSock:sock];
  [_connections addObject:conn];
  conn.source = createSockSource(sock, DISPATCH_SOURCE_TYPE_READ, ^{
    //we don't need weak self here because the singleton server lives forever
    [self receive:conn];
  });
  /*
  dispatch_source_set_cancel_handler(source, ^{
    NSLog(@"canceled");
  });*/
  dispatch_resume(conn.source);
}

-(void) createAcceptSocket
{
  assert(_servsock!=0);
  mysocket accsock;
  struct sockaddr_in saddr;
  socklen_t len = sizeof ( saddr );
  memset( &saddr, 0, sizeof ( saddr ) );
  SOCKERR( ( accsock = accept( _servsock, (struct sockaddr*) &saddr, &len ) ) < 0, FALSE );
  NSLog(@"new connection: sock%d\n", accsock );
  if( accsock >= 0 ) {
    [self newConnection:accsock];
  }
}

- (void)start
{
  int myport;
  _servsock=createTCPServerSocket( 9100, &myport );
  _servsource = createSockSource(_servsock, DISPATCH_SOURCE_TYPE_READ, ^{
    //we don't need weak self here because the singleton server lives forever
    [self createAcceptSocket];
  });
  dispatch_resume(_servsource);
}

-(void)stop
{
  cancelSourceAndSock(&_servsource, &_servsock);
}
@end

@interface MyAppDelegate : UIResponder <UIApplicationDelegate>
{
  UIWindow* _win;
}
@end

static MyTCPServer* getMyTCPServer()
{
  static MyTCPServer* serv=nil;
  if (serv==nil) {
    //create a singleton
    serv=[[MyTCPServer alloc] init];
  }
  return serv;
}

@implementation MyAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  _win=[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  _win.backgroundColor=UIColor.whiteColor;
  UIViewController* c=[[UIViewController alloc] init];
  c.title=@"Title";
  UINavigationController* nav=[[UINavigationController alloc] initWithRootViewController:c];
  NSMutableArray* arr=[NSMutableArray array];
  for(int i=0;i<4;i++) {
    NSString* s=[NSString stringWithFormat:@"C%d",i];
    UIBarButtonItem* b=[[UIBarButtonItem alloc] initWithTitle:s style:UIBarButtonItemStylePlain target:self action:@selector(itemSelected:)];
    [arr insertObject:b atIndex:0];
  }
  c.navigationItem.rightBarButtonItems=arr;
  _win.rootViewController=nav;
  [getMyTCPServer() start];
  [_win makeKeyAndVisible];
  return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
  [getMyTCPServer() stop];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
  [getMyTCPServer() start];
}

-(void)itemSelected: (id)button
{
  NSLog(@"selected:%@",((NSObject*)button).description);
}
@end

int main(int argc, char * argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([MyAppDelegate class]));
  }
}
