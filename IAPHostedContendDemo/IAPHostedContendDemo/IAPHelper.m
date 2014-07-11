//
//  IAPHelper.m
//  In App Rage
//
//  Created by Ray Wenderlich on 9/5/12.
//  Copyright (c) 2012 Razeware LLC. All rights reserved.
//

// 1
#import "IAPHelper.h"
#import <StoreKit/StoreKit.h>

NSString *const IAPHelperProductPurchasedNotification = @"IAPHelperProductPurchasedNotification";

// 2
@interface IAPHelper () <SKProductsRequestDelegate, SKPaymentTransactionObserver>
@end

// 3
@implementation IAPHelper {
    SKProductsRequest * _productsRequest;
    RequestProductsCompletionHandler _completionHandler;
    
    NSSet * _productIdentifiers;
    NSMutableSet * _purchasedProductIdentifiers;
}

- (id)initWithProductIdentifiers:(NSSet *)productIdentifiers {
    
    if ((self = [super init])) {
        
        // Store product identifiers
        _productIdentifiers = productIdentifiers;
        
        // Check for previously purchased products
        _purchasedProductIdentifiers = [NSMutableSet set];
        for (NSString * productIdentifier in _productIdentifiers) {
            BOOL productPurchased = [[NSUserDefaults standardUserDefaults] boolForKey:productIdentifier];
            if (productPurchased) {
                [_purchasedProductIdentifiers addObject:productIdentifier];
                NSLog(@"Previously purchased: %@", productIdentifier);
            } else {
                NSLog(@"Not purchased: %@", productIdentifier);
            }
        }
        
        // Add self as transaction observer
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
        
    }
    return self;
    
}

- (void)requestProductsWithCompletionHandler:(RequestProductsCompletionHandler)completionHandler {
    
    
    // 1
    _completionHandler = [completionHandler copy];
    
    // 2
    _productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:_productIdentifiers];
    _productsRequest.delegate = self;
    [_productsRequest start];
    
}

- (BOOL)productPurchased:(NSString *)productIdentifier {
    return [_purchasedProductIdentifiers containsObject:productIdentifier];
}

- (void)buyProduct:(SKProduct *)product {
    
    NSLog(@"Buying %@...", product.productIdentifier);
    
    SKPayment * payment = [SKPayment paymentWithProduct:product];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
    
}

#pragma mark - SKProductsRequestDelegate

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    
    NSLog(@"Loaded list of products...");
    _productsRequest = nil;
    
    NSArray * skProducts = response.products;
    for (SKProduct * skProduct in skProducts) {
        NSLog(@"Found product: %@ %@ %0.2f",
              skProduct.productIdentifier,
              skProduct.localizedTitle,
              skProduct.price.floatValue);
    }
    
    _completionHandler(YES, skProducts);
    _completionHandler = nil;
    
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    
    NSLog(@"Failed to load list of products.");
    _productsRequest = nil;
    
    _completionHandler(NO, nil);
    _completionHandler = nil;
    
}

#pragma mark SKPaymentTransactionOBserver

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction * transaction in transactions) {
        switch (transaction.transactionState)
        {
            //case SKPaymentTransactionStatePurchased:
            //    [self completeTransaction:transaction];
                break;
            case SKPaymentTransactionStateFailed:
                [self failedTransaction:transaction];
                break;
            //case SKPaymentTransactionStateRestored:
            //    [self restoreTransaction:transaction];
                
            case SKPaymentTransactionStatePurchased:
            case SKPaymentTransactionStateRestored:
            {
                if (transaction.downloads) {
                    [[SKPaymentQueue defaultQueue] startDownloads:transaction.downloads];
                } else {
                    // unlock features
                    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                }
                break;
        	}
                
            default:
                break;
        }
    };
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction {
    NSLog(@"completeTransaction...");
    
    [self provideContentForProductIdentifier:transaction.payment.productIdentifier];
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)restoreTransaction:(SKPaymentTransaction *)transaction {
    NSLog(@"restoreTransaction...");
    
    [self provideContentForProductIdentifier:transaction.originalTransaction.payment.productIdentifier];
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)failedTransaction:(SKPaymentTransaction *)transaction {
    
    NSLog(@"failedTransaction...");
    if (transaction.error.code != SKErrorPaymentCancelled)
    {
        NSLog(@"Transaction error: %@", transaction.error.localizedDescription);
    }
    
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}

- (void)provideContentForProductIdentifier:(NSString *)productIdentifier {
    
    [_purchasedProductIdentifiers addObject:productIdentifier];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:productIdentifier];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:IAPHelperProductPurchasedNotification object:productIdentifier userInfo:nil];
    
}

- (void)restoreCompletedTransactions {
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}



- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray *)downloads;
{
    for (SKDownload *download in downloads) {
        
        if (download.downloadState == SKDownloadStateFinished) {
            [self processDownload:download]; // not written yet
            // now we're done
            [queue finishTransaction:download.transaction];
            
        } else if (download.downloadState == SKDownloadStateActive) {
            
            NSString *productID = download.contentIdentifier; // in app purchase identifier
            NSTimeInterval remaining = download.timeRemaining; // secs
            float progress = download.progress; // 0.0 -> 1.0
            NSLog(@"productID:%@   Progress:%f Remaining:%f", productID, progress, remaining);
            // NOT SHOWN: use the productID to notify your model of download progress...
            
        } else {    // waiting, paused, failed, cancelled
            NSLog(@"Warn: not handled: %ld", (long)download.downloadState);
        }
    }
}



- (void) processDownload:(SKDownload*)download;
{
    // convert url to string, suitable for NSFileManager
    NSString *path = [download.contentURL path];
    
    // files are in Contents directory
    path = [path stringByAppendingPathComponent:@"Contents"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *files = [fileManager contentsOfDirectoryAtPath:path error:&error];
    NSString *dir = [self downloadableContentPathForProductId:download.contentIdentifier]; // not written yet
    
    for (NSString *file in files) {
        NSString *fullPathSrc = [path stringByAppendingPathComponent:file];
        NSString *fullPathDst = [dir stringByAppendingPathComponent:file];
        
        // not allowed to overwrite files - remove destination file
        [fileManager removeItemAtPath:fullPathDst error:NULL];
        
        if ([fileManager moveItemAtPath:fullPathSrc toPath:fullPathDst error:&error] == NO) {
            NSLog(@"Error: unable to move item: %@", error);
        }
    }
    
    // NOT SHOWN: use download.contentIdentifier to tell your model that we've been downloaded
}


/**
 *  Download directory path for product id
 *
 *  @param contentIdentifier product id
 *
 *  @return path
 */
- (NSString*)downloadableContentPathForProductId:(NSString*)contentIdentifier {
    NSError *error = nil;

    NSString *dataPath = [NSString stringWithFormat:@"%@/%@",[self applicationDocumentsDirectory], contentIdentifier];
    if (![[NSFileManager defaultManager] fileExistsAtPath:dataPath])
        [[NSFileManager defaultManager] createDirectoryAtPath:dataPath withIntermediateDirectories:NO attributes:nil error:&error]; //Create folder
    else {
        // delete
        [[NSFileManager defaultManager] removeItemAtPath:dataPath error:&error];
        // create
        [[NSFileManager defaultManager] createDirectoryAtPath:dataPath withIntermediateDirectories:NO attributes:nil error:&error]; //Create folder
    }

    return dataPath;
}

/**
 *  Get Application Home Document
 *
 *  @return path
 */
- (NSString *)applicationDocumentsDirectory
{
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
}


@end