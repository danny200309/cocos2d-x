/****************************************************************************
Copyright (c) 2010-2012 cocos2d-x.org
Copyright (c) 2011      Zynga Inc.

http://www.cocos2d-x.org

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
****************************************************************************/
#import <Foundation/Foundation.h>

#include <string>
#include <stack>
#include "CCString.h"
#include "CCFileUtils.h"
#include "CCDirector.h"
#include "CCSAXParser.h"
#include "CCDictionary.h"
#include "unzip.h"

#include "CCFileUtilsApple.h"

NS_CC_BEGIN

static void addValueToDict(id nsKey, id nsValue, ValueMap& dict);
static void addObjectToNSDict(const std::string& key, Value& value, NSMutableDictionary *dict);

static void addItemToArray(id item, ValueVector& array)
{
    // add string value into array
    if ([item isKindOfClass:[NSString class]])
    {
        array.push_back(Value([item UTF8String]));
        return;
    }
    
    // add number value into array(such as int, float, bool and so on)
    if ([item isKindOfClass:[NSNumber class]])
    {
        array.push_back(Value([item doubleValue]));
        return;
    }
    
    // add dictionary value into array
    if ([item isKindOfClass:[NSDictionary class]])
    {
        ValueMap dict;
        for (id subKey in [item allKeys])
        {
            id subValue = [item objectForKey:subKey];
            addValueToDict(subKey, subValue, dict);
        }
        
        array.push_back(Value(dict));
        return;
    }
    
    // add array value into array
    if ([item isKindOfClass:[NSArray class]])
    {
        ValueVector subArray;
        for (id subItem in item)
        {
            addItemToArray(subItem, subArray);
        }
        array.push_back(Value(subArray));
        return;
    }
}

static void addObjectToNSArray(Value& value, NSMutableArray *array)
{
    // add string into array
    if (value.getType() == Value::Type::STRING)
    {
        NSString *strElement = [NSString stringWithCString:value.asString().c_str() encoding:NSUTF8StringEncoding];
        [array addObject:strElement];
        return;
    }
    
    // add array into array
    if (value.getType() == Value::Type::VECTOR)
    {
        NSMutableArray *arrElement = [NSMutableArray array];
        
        ValueVector valueArray = value.asValueVector();
        
        std::for_each(valueArray.begin(), valueArray.end(), [=](Value& e){
            addObjectToNSArray(e, arrElement);
        });
        
        [array addObject:arrElement];
        return;
    }
    
    // add dictionary value into array
    if (value.getType() == Value::Type::MAP)
    {
        NSMutableDictionary *dictElement = [NSMutableDictionary dictionary];

        auto valueDict = value.asValueMap();
        for (auto iter = valueDict.begin(); iter != valueDict.end(); ++iter)
        {
            addObjectToNSDict(iter->first, iter->second, dictElement);
        }
        
        [array addObject:dictElement];
    }
}

static void addValueToDict(id nsKey, id nsValue, ValueMap& dict)
{
    // the key must be a string
    CCASSERT([nsKey isKindOfClass:[NSString class]], "The key should be a string!");
    std::string key = [nsKey UTF8String];
    
    // the value is a string
    if ([nsValue isKindOfClass:[NSString class]])
    {
        dict[key] = Value([nsValue UTF8String]);
        return;
    }
    
    // the value is a number
    if ([nsValue isKindOfClass:[NSNumber class]])
    {
        dict[key] = Value([nsValue doubleValue]);
        return;
    }
    
    // the value is a new dictionary
    if ([nsValue isKindOfClass:[NSDictionary class]])
    {
        ValueMap subDict;
        
        for (id subKey in [nsValue allKeys])
        {
            id subValue = [nsValue objectForKey:subKey];
            addValueToDict(subKey, subValue, subDict);
        }
        dict[key] = Value(subDict);
        return;
    }
    
    // the value is a array
    if ([nsValue isKindOfClass:[NSArray class]])
    {
        ValueVector valueArray;

        for (id item in nsValue)
        {
            addItemToArray(item, valueArray);
        }
        dict[key] = Value(valueArray);
        return;
    }
}

static void addObjectToNSDict(const std::string& key, Value& value, NSMutableDictionary *dict)
{
    NSString *NSkey = [NSString stringWithCString:key.c_str() encoding:NSUTF8StringEncoding];
    
    // the object is a Dictionary
    if (value.getType() == Value::Type::MAP)
    {
        NSMutableDictionary *dictElement = [NSMutableDictionary dictionary];
        ValueMap subDict = value.asValueMap();
        for (auto iter = subDict.begin(); iter != subDict.end(); ++iter)
        {
            addObjectToNSDict(iter->first, iter->second, dictElement);
        }
        
        [dict setObject:dictElement forKey:NSkey];
        return;
    }
    
    // the object is a String
    if (value.getType() == Value::Type::STRING)
    {
        NSString *strElement = [NSString stringWithCString:value.asString().c_str() encoding:NSUTF8StringEncoding];
        [dict setObject:strElement forKey:NSkey];
        return;
    }
    
    // the object is a Array
    if (value.getType() == Value::Type::VECTOR)
    {
        NSMutableArray *arrElement = [NSMutableArray array];
        
        ValueVector array = value.asValueVector();
        
        std::for_each(array.begin(), array.end(), [=](Value& v){
            addObjectToNSArray(v, arrElement);
        });

        [dict setObject:arrElement forKey:NSkey];
        return;
    }
}


#pragma mark - FileUtils

static NSFileManager* s_fileManager = [NSFileManager defaultManager];

FileUtils* FileUtils::getInstance()
{
    if (s_sharedFileUtils == NULL)
    {
        s_sharedFileUtils = new FileUtilsApple();
        if(!s_sharedFileUtils->init())
        {
          delete s_sharedFileUtils;
          s_sharedFileUtils = NULL;
          CCLOG("ERROR: Could not init CCFileUtilsApple");
        }
    }
    return s_sharedFileUtils;
}


std::string FileUtilsApple::getWritablePath() const
{
    // save to document folder
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    std::string strRet = [documentsDirectory UTF8String];
    strRet.append("/");
    return strRet;
}

bool FileUtilsApple::isFileExist(const std::string& strFilePath) const
{
    if(strFilePath.length() == 0)
    {
        return false;
    }

    bool bRet = false;
    
    if (strFilePath[0] != '/')
    {
        std::string path;
        std::string file;
        size_t pos = strFilePath.find_last_of("/");
        if (pos != std::string::npos)
        {
            file = strFilePath.substr(pos+1);
            path = strFilePath.substr(0, pos+1);
        }
        else
        {
            file = strFilePath;
        }
        
        NSString* fullpath = [[NSBundle mainBundle] pathForResource:[NSString stringWithUTF8String:file.c_str()]
                                                             ofType:nil
                                                        inDirectory:[NSString stringWithUTF8String:path.c_str()]];
        if (fullpath != nil) {
            bRet = true;
        }
    }
    else
    {
        // Search path is an absolute path.
        if ([s_fileManager fileExistsAtPath:[NSString stringWithUTF8String:strFilePath.c_str()]]) {
            bRet = true;
        }
    }
    
    return bRet;
}

std::string FileUtilsApple::getFullPathForDirectoryAndFilename(const std::string& strDirectory, const std::string& strFilename)
{
    if (strDirectory[0] != '/')
    {
        NSString* fullpath = [[NSBundle mainBundle] pathForResource:[NSString stringWithUTF8String:strFilename.c_str()]
                                                             ofType:nil
                                                        inDirectory:[NSString stringWithUTF8String:strDirectory.c_str()]];
        if (fullpath != nil) {
            return [fullpath UTF8String];
        }
    }
    else
    {
        std::string fullPath = strDirectory+strFilename;
        // Search path is an absolute path.
        if ([s_fileManager fileExistsAtPath:[NSString stringWithUTF8String:fullPath.c_str()]]) {
            return fullPath;
        }
    }
    return "";
}

ValueMap FileUtilsApple::getValueMapFromFile(const std::string& filename)
{
    std::string fullPath = fullPathForFilename(filename);
    NSString* path = [NSString stringWithUTF8String:fullPath.c_str()];
    NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile:path];
    
    ValueMap ret;
    
    if (dict != nil)
    {
        for (id key in [dict allKeys])
        {
            id value = [dict objectForKey:key];
            addValueToDict(key, value, ret);
        }
    }
    return ret;
}

bool FileUtilsApple::writeToFile(ValueMap& dict, const std::string &fullPath)
{
    //CCLOG("iOS||Mac Dictionary %d write to file %s", dict->_ID, fullPath.c_str());
    NSMutableDictionary *nsDict = [NSMutableDictionary dictionary];
    
    for (auto iter = dict.begin(); iter != dict.end(); ++iter)
    {
        addObjectToNSDict(iter->first, iter->second, nsDict);
    }
    
    NSString *file = [NSString stringWithUTF8String:fullPath.c_str()];
    // do it atomically
    [nsDict writeToFile:file atomically:YES];
    
    return true;
}

ValueVector FileUtilsApple::getValueVectorFromFile(const std::string& filename)
{
    //    NSString* pPath = [NSString stringWithUTF8String:pFileName];
    //    NSString* pathExtension= [pPath pathExtension];
    //    pPath = [pPath stringByDeletingPathExtension];
    //    pPath = [[NSBundle mainBundle] pathForResource:pPath ofType:pathExtension];
    //    fixing cannot read data using Array::createWithContentsOfFile
    std::string fullPath = fullPathForFilename(filename);
    NSString* path = [NSString stringWithUTF8String:fullPath.c_str()];
    NSArray* array = [NSArray arrayWithContentsOfFile:path];
    
    ValueVector ret;
    
    for (id value in array)
    {
        addItemToArray(value, ret);
    }
    
    return ret;
}

NS_CC_END

